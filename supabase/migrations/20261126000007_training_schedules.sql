-- =====================================================================
-- SwimBase update: training schedules for each group
-- =====================================================================
-- Plain-English summary:
--   * Each group has a WEEKLY pattern, e.g. Senior: Mon to Fri 4:30-7:00 PM,
--     plus Tue and Thu 6:00-7:00 AM. A pattern line starts on a date and
--     can be given a last day, so changes never rewrite the past.
--   * The app turns the weekly pattern into real dated SESSIONS for the
--     next 90 days, and tops them up every night. Attendance (next phase)
--     is taken on these sessions.
--   * A coach can add a one-off session, cancel or restore a session,
--     or change one day's time, for one group or several at once.
--   * REST DAYS / BREAKS can be set for one group or the whole club. They
--     cancel the sessions inside them; removing the rest day brings the
--     sessions back.
--   * A swimmer follows the group they are in on each date, so a moved
--     swimmer sees the new group's sessions from the move date.
--   * Who can edit a group's schedule: the head coach, assistant coaches
--     with the "create groups" switch, and coaches assigned to that group.
--   * Everyone in the club can see the schedules (they are not private).
--
-- Cancelled sessions keep the time they were cancelled, so the push
-- notification phase can tell families later.
--
-- Run this once in the Supabase SQL Editor.
-- =====================================================================

create type public.session_status as enum ('scheduled', 'cancelled');
create type public.rest_kind as enum ('rest_day', 'break');

-- ---------- Tables ----------------------------------------------------

-- One line of a group's weekly pattern.
create table public.weekly_sessions (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null,
  group_id    uuid not null,
  weekday     smallint not null check (weekday between 1 and 7), -- 1 = Monday ... 7 = Sunday
  start_time  time not null,
  end_time    time not null,
  label       text,          -- optional, e.g. "AM" or "Dryland"
  venue       text,
  starts_on   date not null,
  ends_on     date,          -- last day it runs; empty = keeps going
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  check (end_time > start_time),
  check (ends_on is null or ends_on >= starts_on),
  foreign key (group_id, club_id) references public.groups (id, club_id) on delete cascade
);
create index weekly_sessions_group_idx on public.weekly_sessions (group_id);

-- A rest day or break, for one group (group_id set) or the whole club.
create table public.rest_days (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references public.clubs (id) on delete cascade,
  group_id    uuid,
  start_date  date not null,
  end_date    date not null,
  kind        public.rest_kind not null default 'rest_day',
  title       text,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  check (end_date >= start_date),
  foreign key (group_id, club_id) references public.groups (id, club_id) on delete cascade
);
create index rest_days_club_idx on public.rest_days (club_id, start_date);

-- One real training session on one date for one group.
create table public.sessions (
  id                 uuid primary key default gen_random_uuid(),
  club_id            uuid not null,
  group_id           uuid not null,
  session_date       date not null,
  start_time         time not null,
  end_time           time not null,
  label              text,
  venue              text,
  -- Which weekly line made it. Empty for a one-off session.
  weekly_session_id  uuid references public.weekly_sessions (id) on delete set null,
  status             public.session_status not null default 'scheduled',
  cancel_reason      text,
  -- Set when a rest day cancelled it, so removing the rest day restores it.
  rest_day_id        uuid references public.rest_days (id) on delete set null,
  cancelled_by       uuid references auth.users (id) on delete set null,
  cancelled_at       timestamptz,
  created_by         uuid references auth.users (id) on delete set null,
  created_at         timestamptz not null default now(),
  check (end_time > start_time),
  unique (weekly_session_id, session_date),
  unique (id, club_id),
  foreign key (group_id, club_id) references public.groups (id, club_id) on delete cascade
);
create index sessions_group_date_idx on public.sessions (group_id, session_date);
create index sessions_club_date_idx on public.sessions (club_id, session_date);

-- ---------- Privacy rules ---------------------------------------------

alter table public.weekly_sessions enable row level security;
alter table public.rest_days       enable row level security;
alter table public.sessions        enable row level security;

create policy "Members see weekly schedules" on public.weekly_sessions
  for select to authenticated using (public.is_club_member(club_id) or public.is_superadmin());
create policy "Members see rest days" on public.rest_days
  for select to authenticated using (public.is_club_member(club_id) or public.is_superadmin());
create policy "Members see sessions" on public.sessions
  for select to authenticated using (public.is_club_member(club_id) or public.is_superadmin());

-- Reading only. Every change goes through the functions below.
revoke all on public.weekly_sessions, public.rest_days, public.sessions from anon;
revoke insert, update, delete on public.weekly_sessions, public.rest_days, public.sessions from authenticated;
grant select on public.weekly_sessions, public.rest_days, public.sessions to authenticated;

-- ---------- Helpers ---------------------------------------------------

-- Can the signed-in person change this group's schedule?
create function public.can_edit_schedule(p_group_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.groups g
    where g.id = p_group_id
      and (public.can_manage_groups(g.club_id)
           or (public.is_coach(g.club_id) and exists (
                 select 1 from public.group_coaches gc
                 where gc.group_id = g.id and gc.user_id = auth.uid())))
  )
$$;

create function public.require_schedule_editor(p_group_id uuid)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare
  v_club uuid;
begin
  perform public.require_signed_in();
  select club_id into v_club from public.groups where id = p_group_id and archived_at is null;
  if v_club is null then
    raise exception 'That group doesn''t exist or is archived.';
  end if;
  if not public.can_edit_schedule(p_group_id) then
    raise exception 'You can''t change this group''s schedule. Ask your head coach.' using errcode = '42501';
  end if;
  return v_club;
end;
$$;

-- How far ahead dated sessions are created.
create function public.schedule_horizon_days()
returns integer language sql immutable as $$ select 90 $$;

-- The rest day (if any) covering a group on a date.
create function public.rest_day_for(p_club_id uuid, p_group_id uuid, p_date date)
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.rest_days
  where club_id = p_club_id
    and (group_id is null or group_id = p_group_id)
    and p_date between start_date and end_date
  order by created_at
  limit 1
$$;

-- Creates the dated sessions for one group from today up to the horizon.
-- Sessions that already exist are left alone. Returns how many were added.
create function public.fill_sessions(p_group_id uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_club uuid;
  v_today date;
  v_count integer;
begin
  select club_id into v_club from public.groups where id = p_group_id and archived_at is null;
  if v_club is null then
    return 0;
  end if;
  v_today := public.club_today(v_club);

  with candidates as (
    select w.*, d::date as on_date
    from public.weekly_sessions w
    cross join generate_series(v_today, v_today + public.schedule_horizon_days(), interval '1 day') d
    where w.group_id = p_group_id
      and extract(isodow from d) = w.weekday
      and d::date >= w.starts_on
      and (w.ends_on is null or d::date <= w.ends_on)
  ), added as (
    insert into public.sessions
      (club_id, group_id, session_date, start_time, end_time, label, venue,
       weekly_session_id, status, rest_day_id, cancelled_at, created_by)
    select c.club_id, c.group_id, c.on_date, c.start_time, c.end_time, c.label, c.venue, c.id,
           case when r.id is null then 'scheduled' else 'cancelled' end::public.session_status,
           r.id,
           case when r.id is null then null else now() end,
           c.created_by
    from candidates c
    left join lateral (select public.rest_day_for(c.club_id, c.group_id, c.on_date) as id) r on true
    on conflict (weekly_session_id, session_date) do nothing
    returning 1
  )
  select count(*) into v_count from added;
  return v_count;
end;
$$;

-- Run every night: keeps every active group's sessions 90 days ahead.
create function public.top_up_all_sessions()
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_total integer := 0;
  g record;
begin
  for g in select id from public.groups where archived_at is null loop
    v_total := v_total + public.fill_sessions(g.id);
  end loop;
  return v_total;
end;
$$;

-- ---------- Weekly pattern --------------------------------------------

-- Adds one line to a group's weekly pattern, starting on p_starts_on
-- (today if left out), and creates its sessions.
create function public.add_weekly_session(
  p_group_id uuid,
  p_weekday integer,
  p_start_time time,
  p_end_time time,
  p_label text default null,
  p_venue text default null,
  p_starts_on date default null
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_club uuid := public.require_schedule_editor(p_group_id);
  v_id uuid;
begin
  if p_end_time <= p_start_time then
    raise exception 'The end time must be after the start time.';
  end if;
  insert into public.weekly_sessions
    (club_id, group_id, weekday, start_time, end_time, label, venue, starts_on, created_by)
  values
    (v_club, p_group_id, p_weekday, p_start_time, p_end_time,
     nullif(trim(p_label), ''), nullif(trim(p_venue), ''),
     greatest(coalesce(p_starts_on, public.club_today(v_club)), public.club_today(v_club)),
     auth.uid())
  returning id into v_id;
  perform public.fill_sessions(p_group_id);
  return v_id;
end;
$$;

-- Stops a weekly line after p_last_day (yesterday if left out, so it stops
-- from today). Its sessions after that day are removed; earlier ones stay.
create function public.end_weekly_session(p_weekly_session_id uuid, p_last_day date default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_line public.weekly_sessions;
  v_today date;
  v_last date;
begin
  select * into v_line from public.weekly_sessions where id = p_weekly_session_id;
  if v_line.id is null then
    raise exception 'That weekly session no longer exists.';
  end if;
  perform public.require_schedule_editor(v_line.group_id);
  v_today := public.club_today(v_line.club_id);
  v_last := coalesce(p_last_day, v_today - 1);
  if v_last < v_today - 1 then
    raise exception 'Pick today or a later date. Past sessions stay as they were.';
  end if;

  delete from public.sessions
   where weekly_session_id = v_line.id and session_date > v_last;

  if v_last < v_line.starts_on then
    -- It never ran: remove the line completely.
    delete from public.weekly_sessions where id = v_line.id;
  else
    update public.weekly_sessions set ends_on = v_last where id = v_line.id;
  end if;
end;
$$;

-- Copies another group's current weekly pattern into this group, starting
-- on p_starts_on (today if left out). Returns how many lines were copied.
create function public.copy_weekly_schedule(p_from_group_id uuid, p_to_group_id uuid, p_starts_on date default null)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_club uuid := public.require_schedule_editor(p_to_group_id);
  v_start date;
  v_count integer;
begin
  if not exists (select 1 from public.groups where id = p_from_group_id and club_id = v_club) then
    raise exception 'Pick a group from the same club.';
  end if;
  v_start := greatest(coalesce(p_starts_on, public.club_today(v_club)), public.club_today(v_club));
  insert into public.weekly_sessions
    (club_id, group_id, weekday, start_time, end_time, label, venue, starts_on, created_by)
  select v_club, p_to_group_id, weekday, start_time, end_time, label, venue, v_start, auth.uid()
  from public.weekly_sessions
  where group_id = p_from_group_id and (ends_on is null or ends_on >= v_start);
  get diagnostics v_count = row_count;
  perform public.fill_sessions(p_to_group_id);
  return v_count;
end;
$$;

-- ---------- One day at a time -----------------------------------------

-- Adds a one-off session on one date for one or several groups.
create function public.add_one_off_session(
  p_group_ids uuid[],
  p_date date,
  p_start_time time,
  p_end_time time,
  p_label text default null,
  p_venue text default null
)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_club uuid;
  v_group uuid;
  v_count integer := 0;
begin
  if p_group_ids is null or cardinality(p_group_ids) = 0 then
    raise exception 'Choose at least one group.';
  end if;
  if p_end_time <= p_start_time then
    raise exception 'The end time must be after the start time.';
  end if;
  foreach v_group in array p_group_ids loop
    v_club := public.require_schedule_editor(v_group);
    if p_date < public.club_today(v_club) then
      raise exception 'Pick today or a later date.';
    end if;
    insert into public.sessions
      (club_id, group_id, session_date, start_time, end_time, label, venue, created_by)
    values
      (v_club, v_group, p_date, p_start_time, p_end_time,
       nullif(trim(p_label), ''), nullif(trim(p_venue), ''), auth.uid());
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Cancels one or several sessions. Families see them as cancelled.
create function public.cancel_sessions(p_session_ids uuid[], p_reason text default null)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_session public.sessions;
  v_count integer := 0;
begin
  perform public.require_signed_in();
  for v_session in select * from public.sessions where id = any (p_session_ids) for update loop
    perform public.require_schedule_editor(v_session.group_id);
    if v_session.status = 'cancelled' then
      continue;
    end if;
    if v_session.session_date < public.club_today(v_session.club_id) then
      raise exception 'Sessions in the past can''t be cancelled.';
    end if;
    update public.sessions
       set status = 'cancelled', cancel_reason = nullif(trim(p_reason), ''),
           cancelled_by = auth.uid(), cancelled_at = now()
     where id = v_session.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Brings back a cancelled session.
create function public.restore_session(p_session_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_session public.sessions;
begin
  select * into v_session from public.sessions where id = p_session_id for update;
  if v_session.id is null then
    raise exception 'That session no longer exists.';
  end if;
  perform public.require_schedule_editor(v_session.group_id);
  if v_session.rest_day_id is not null then
    raise exception 'This session is inside a rest day. Remove the rest day to bring it back.';
  end if;
  update public.sessions
     set status = 'scheduled', cancel_reason = null, cancelled_by = null, cancelled_at = null
   where id = p_session_id;
end;
$$;

-- Changes the time (and optionally the venue) of one session only.
create function public.change_session_time(
  p_session_id uuid,
  p_start_time time,
  p_end_time time,
  p_venue text default null
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_session public.sessions;
begin
  select * into v_session from public.sessions where id = p_session_id for update;
  if v_session.id is null then
    raise exception 'That session no longer exists.';
  end if;
  perform public.require_schedule_editor(v_session.group_id);
  if p_end_time <= p_start_time then
    raise exception 'The end time must be after the start time.';
  end if;
  update public.sessions
     set start_time = p_start_time, end_time = p_end_time,
         venue = coalesce(nullif(trim(p_venue), ''), venue)
   where id = p_session_id;
end;
$$;

-- ---------- Rest days and breaks --------------------------------------

-- Sets a rest day or break from p_start to p_end for the given groups, or
-- for the whole club when p_group_ids is empty (head coach or "create
-- groups" switch only). Cancels the sessions inside. Returns how many
-- sessions were cancelled.
create function public.add_rest_days(
  p_club_id uuid,
  p_group_ids uuid[],
  p_start date,
  p_end date,
  p_kind public.rest_kind default 'rest_day',
  p_title text default null
)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_group uuid;
  v_rest uuid;
  v_count integer := 0;
  v_n integer;
begin
  perform public.require_signed_in();
  if p_end < p_start then
    raise exception 'The last day must be on or after the first day.';
  end if;

  if p_group_ids is null or cardinality(p_group_ids) = 0 then
    if not public.can_manage_groups(p_club_id) then
      raise exception 'Only the head coach can set a rest day for the whole club.' using errcode = '42501';
    end if;
    insert into public.rest_days (club_id, group_id, start_date, end_date, kind, title, created_by)
    values (p_club_id, null, p_start, p_end, coalesce(p_kind, 'rest_day'), nullif(trim(p_title), ''), auth.uid())
    returning id into v_rest;
    update public.sessions
       set status = 'cancelled', rest_day_id = v_rest, cancelled_by = auth.uid(), cancelled_at = now()
     where club_id = p_club_id and status = 'scheduled'
       and session_date between p_start and p_end;
    get diagnostics v_n = row_count;
    return v_n;
  end if;

  foreach v_group in array p_group_ids loop
    if public.require_schedule_editor(v_group) <> p_club_id then
      raise exception 'Pick groups from this club.';
    end if;
    insert into public.rest_days (club_id, group_id, start_date, end_date, kind, title, created_by)
    values (p_club_id, v_group, p_start, p_end, coalesce(p_kind, 'rest_day'), nullif(trim(p_title), ''), auth.uid())
    returning id into v_rest;
    update public.sessions
       set status = 'cancelled', rest_day_id = v_rest, cancelled_by = auth.uid(), cancelled_at = now()
     where group_id = v_group and status = 'scheduled'
       and session_date between p_start and p_end;
    get diagnostics v_n = row_count;
    v_count := v_count + v_n;
  end loop;
  return v_count;
end;
$$;

-- Removes a rest day and brings back the sessions it cancelled (unless
-- another rest day still covers them).
create function public.remove_rest_day(p_rest_day_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_rest public.rest_days;
  s record;
  v_other uuid;
begin
  perform public.require_signed_in();
  select * into v_rest from public.rest_days where id = p_rest_day_id;
  if v_rest.id is null then
    raise exception 'That rest day no longer exists.';
  end if;
  if v_rest.group_id is null then
    if not public.can_manage_groups(v_rest.club_id) then
      raise exception 'Only the head coach can remove a whole-club rest day.' using errcode = '42501';
    end if;
  else
    perform public.require_schedule_editor(v_rest.group_id);
  end if;

  -- Bring back the sessions it cancelled, unless another rest day still
  -- covers them.
  for s in
    select id, club_id, group_id, session_date from public.sessions
    where rest_day_id = p_rest_day_id
    for update
  loop
    v_other := public.rest_day_for(s.club_id, s.group_id, s.session_date);
    if v_other is null or v_other = p_rest_day_id then
      -- Look again, ignoring the rest day being removed.
      select id into v_other from public.rest_days
       where club_id = s.club_id and id <> p_rest_day_id
         and (group_id is null or group_id = s.group_id)
         and s.session_date between start_date and end_date
       order by created_at limit 1;
    end if;
    if v_other is null then
      update public.sessions
         set status = 'scheduled', rest_day_id = null, cancelled_by = null, cancelled_at = null
       where id = s.id;
    else
      update public.sessions set rest_day_id = v_other where id = s.id;
    end if;
  end loop;

  delete from public.rest_days where id = p_rest_day_id;
end;
$$;

-- ---------- A swimmer's own calendar ----------------------------------

-- The training days for one swimmer between two dates (at most 120 days),
-- following the group they are in on each date, including scheduled moves.
-- Each row is a session, or a rest day with no session (session_id empty).
create function public.swimmer_schedule(p_swimmer_id uuid, p_from date, p_to date)
returns table (
  session_date  date,
  group_id      uuid,
  group_name    text,
  session_id    uuid,
  start_time    time,
  end_time      time,
  label         text,
  venue         text,
  status        text,   -- 'scheduled', 'cancelled' or 'rest'
  note          text    -- cancel reason or rest day title
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.require_signed_in();
  if not (public.can_see_swimmer(p_swimmer_id) or public.is_superadmin()) then
    raise exception 'You can''t see this swimmer.' using errcode = '42501';
  end if;
  if p_to < p_from or p_to - p_from > 120 then
    raise exception 'Pick a range of up to 120 days.';
  end if;

  return query
  with days as (
    select d::date as day from generate_series(p_from, p_to, interval '1 day') d
  ), in_group as (
    select days.day,
           (select m.to_group_id from public.group_moves m
             where m.swimmer_id = p_swimmer_id
               and m.status in ('done', 'scheduled')
               and m.effective_date <= days.day
             order by m.effective_date desc, m.recorded_at desc
             limit 1) as group_id
    from days
  ), with_sessions as (
    select ig.day, ig.group_id, g.name as group_name, s.id as session_id,
           s.start_time, s.end_time, s.label, s.venue, s.status::text as status,
           coalesce(s.cancel_reason, r.title,
                    case r.kind when 'break' then 'Break' when 'rest_day' then 'Rest day' end) as note
    from in_group ig
    join public.groups g on g.id = ig.group_id
    join public.sessions s on s.group_id = ig.group_id and s.session_date = ig.day
    left join public.rest_days r on r.id = s.rest_day_id
  ), rest_only as (
    select ig.day, ig.group_id, g.name, null::uuid, null::time, null::time, null::text, null::text,
           'rest'::text,
           coalesce(r.title, case r.kind when 'break' then 'Break' else 'Rest day' end)
    from in_group ig
    join public.groups g on g.id = ig.group_id
    join lateral (
      select * from public.rest_days rd
      where rd.club_id = g.club_id
        and (rd.group_id is null or rd.group_id = ig.group_id)
        and ig.day between rd.start_date and rd.end_date
      order by rd.created_at limit 1
    ) r on true
    where not exists (select 1 from with_sessions ws where ws.day = ig.day)
  )
  select * from with_sessions
  union all
  select * from rest_only
  order by 1, 5 nulls first;
end;
$$;

-- ---------- Archiving a group -----------------------------------------
-- An archived group's future sessions are removed; restoring it brings
-- its weekly pattern back.

create function public.sync_sessions_on_archive()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.archived_at is not null and old.archived_at is null then
    delete from public.sessions
     where group_id = new.id and session_date >= public.club_today(new.club_id);
  elsif new.archived_at is null and old.archived_at is not null then
    perform public.fill_sessions(new.id);
  end if;
  return new;
end;
$$;

create trigger groups_sync_sessions
  after update of archived_at on public.groups
  for each row execute function public.sync_sessions_on_archive();

-- ---------- Who may call what -----------------------------------------

revoke execute on function
  public.fill_sessions(uuid),
  public.top_up_all_sessions(),
  public.require_schedule_editor(uuid),
  public.rest_day_for(uuid, uuid, date),
  public.sync_sessions_on_archive()
from public, anon, authenticated;

grant execute on function
  public.can_edit_schedule(uuid),
  public.schedule_horizon_days(),
  public.add_weekly_session(uuid, integer, time, time, text, text, date),
  public.end_weekly_session(uuid, date),
  public.copy_weekly_schedule(uuid, uuid, date),
  public.add_one_off_session(uuid[], date, time, time, text, text),
  public.cancel_sessions(uuid[], text),
  public.restore_session(uuid),
  public.change_session_time(uuid, time, time, text),
  public.add_rest_days(uuid, uuid[], date, date, public.rest_kind, text),
  public.remove_rest_day(uuid),
  public.swimmer_schedule(uuid, date, date)
to authenticated;

-- ---------- Nightly top-up --------------------------------------------

do $migration$
begin
  -- The automatic tests use a plain database without the scheduler.
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    raise notice 'pg_cron is not available here; skipping the schedule.';
    return;
  end if;
  create extension if not exists pg_cron;
  -- 16:15 UTC = 12:15 AM in Manila.
  perform cron.schedule('top-up-sessions', '15 16 * * *', 'select public.top_up_all_sessions()');
end
$migration$;
