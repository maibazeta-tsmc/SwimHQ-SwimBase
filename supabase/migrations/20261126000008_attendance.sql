-- =====================================================================
-- SwimBase update: attendance
-- =====================================================================
-- Plain-English summary:
--   * Coaches take attendance on each training session (from the
--     schedules update). Any coach can take attendance for any group.
--   * Each swimmer gets one mark per session: Present, Absent, Late,
--     Early-Up, DNF (did not finish) or Excused. Excused needs a reason:
--     Medical, School or Family. A coach can add a short note that only
--     coaches see.
--   * Scoring: Present = 1, Late / Early-Up / DNF = half, Absent = 0.
--     Excused marks and rest days are left out of the percentage.
--   * Marks can be taken or changed until 7 days after the session.
--     After that only the head coach can change them.
--   * Every change is kept (who changed what, and when).
--   * Cancelled sessions can't take attendance, and a session that has
--     attendance can't be cancelled until its attendance is cleared.
--   * The list for a session holds the swimmers who were in that group on
--     that date, so a moved swimmer appears in the right group.
--   * Swimmers and parents read their own marks (parents only their own
--     children) through swimmer_attendance(). They never see coach notes.
--
-- Run this once in the Supabase SQL Editor.
-- =====================================================================

create type public.attendance_status as enum ('present', 'absent', 'late', 'early_up', 'dnf', 'excused');
create type public.excuse_reason as enum ('medical', 'school', 'family');

-- ---------- Tables ----------------------------------------------------

-- One swimmer's mark for one session.
create table public.attendance (
  id             uuid primary key default gen_random_uuid(),
  club_id        uuid not null,
  session_id     uuid not null,
  swimmer_id     uuid not null,
  status         public.attendance_status not null,
  excuse_reason  public.excuse_reason,
  note           text,          -- coaches only
  marked_by      uuid references auth.users (id) on delete set null,
  marked_at      timestamptz not null default now(),
  unique (session_id, swimmer_id),
  check ((status = 'excused') = (excuse_reason is not null)),
  foreign key (session_id, club_id) references public.sessions (id, club_id) on delete cascade,
  foreign key (swimmer_id, club_id) references public.swimmers (id, club_id) on delete cascade
);
create index attendance_swimmer_idx on public.attendance (swimmer_id);
create index attendance_club_idx on public.attendance (club_id, marked_at);

-- Every change to a mark, kept for good. Written automatically.
create table public.attendance_changes (
  id             bigint generated always as identity primary key,
  club_id        uuid not null references public.clubs (id) on delete cascade,
  session_id     uuid not null,
  swimmer_id     uuid not null,
  old_status     public.attendance_status,  -- empty = was not marked
  old_reason     public.excuse_reason,
  new_status     public.attendance_status,  -- empty = mark cleared
  new_reason     public.excuse_reason,
  changed_by     uuid references auth.users (id) on delete set null,
  changed_at     timestamptz not null default now()
);
create index attendance_changes_session_idx on public.attendance_changes (session_id, changed_at);

-- ---------- Privacy rules ---------------------------------------------

alter table public.attendance         enable row level security;
alter table public.attendance_changes enable row level security;

-- Coaches (and the superadmin, read only) see the raw marks with notes.
-- Families read their own through swimmer_attendance() below.
create policy "Coaches see attendance" on public.attendance
  for select to authenticated using (public.is_coach(club_id) or public.is_superadmin());
create policy "Coaches see attendance changes" on public.attendance_changes
  for select to authenticated using (public.is_coach(club_id) or public.is_superadmin());

-- Reading only. Every change goes through the functions below.
revoke all on public.attendance, public.attendance_changes from anon;
revoke insert, update, delete on public.attendance, public.attendance_changes from authenticated;
grant select on public.attendance, public.attendance_changes to authenticated;

-- ---------- Helpers ---------------------------------------------------

-- The group a swimmer was (or will be) in on a date. Empty if none,
-- e.g. before they joined or after they left the club.
create function public.swimmer_group_on(p_swimmer_id uuid, p_date date)
returns uuid language sql stable security definer set search_path = public as $$
  select m.to_group_id from public.group_moves m
  where m.swimmer_id = p_swimmer_id
    and m.status in ('done', 'scheduled')
    and m.effective_date <= p_date
  order by m.effective_date desc, m.recorded_at desc
  limit 1
$$;

-- Points for one mark: 1, 0.5 or 0. Empty for Excused (not counted).
create function public.attendance_points(p_status public.attendance_status)
returns numeric language sql immutable as $$
  select case p_status
    when 'present' then 1
    when 'late' then 0.5
    when 'early_up' then 0.5
    when 'dnf' then 0.5
    when 'absent' then 0
    else null
  end::numeric
$$;

-- Checks the signed-in person may mark this session now, and returns it.
create function public.require_attendance_taker(p_session_id uuid)
returns public.sessions language plpgsql stable security definer set search_path = public as $$
declare
  v_session public.sessions;
  v_today date;
begin
  perform public.require_signed_in();
  select * into v_session from public.sessions where id = p_session_id;
  if v_session.id is null then
    raise exception 'That session no longer exists.';
  end if;
  if not public.is_coach(v_session.club_id) then
    raise exception 'Only coaches can take attendance.' using errcode = '42501';
  end if;
  if v_session.status = 'cancelled' then
    raise exception 'This session was cancelled, so it can''t take attendance.';
  end if;
  v_today := public.club_today(v_session.club_id);
  if v_session.session_date > v_today then
    raise exception 'This session hasn''t happened yet. Take attendance on the day.';
  end if;
  if v_session.session_date < v_today - 7 and not public.is_head_coach(v_session.club_id) then
    raise exception 'This session was more than 7 days ago. Only the head coach can change it now.'
      using errcode = '42501';
  end if;
  return v_session;
end;
$$;

-- Keeps the change history. Runs on every insert, update and delete.
create function public.log_attendance_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.attendance_changes
      (club_id, session_id, swimmer_id, new_status, new_reason, changed_by)
    values (new.club_id, new.session_id, new.swimmer_id, new.status, new.excuse_reason, auth.uid());
  elsif tg_op = 'UPDATE' then
    if new.status is distinct from old.status or new.excuse_reason is distinct from old.excuse_reason then
      insert into public.attendance_changes
        (club_id, session_id, swimmer_id, old_status, old_reason, new_status, new_reason, changed_by)
      values (new.club_id, new.session_id, new.swimmer_id, old.status, old.excuse_reason,
              new.status, new.excuse_reason, auth.uid());
    end if;
  else
    -- Skip when the whole club is being removed.
    if exists (select 1 from public.clubs where id = old.club_id) then
      insert into public.attendance_changes
        (club_id, session_id, swimmer_id, old_status, old_reason, changed_by)
      values (old.club_id, old.session_id, old.swimmer_id, old.status, old.excuse_reason, auth.uid());
    end if;
  end if;
  return null;
end;
$$;

create trigger attendance_log_change
  after insert or update or delete on public.attendance
  for each row execute function public.log_attendance_change();

-- A session with attendance can't be cancelled (by hand or by a rest day)
-- or removed (by ending a weekly line or archiving its group).
create function public.protect_marked_sessions()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.status = 'cancelled' and old.status <> 'cancelled'
       and exists (select 1 from public.attendance where session_id = old.id) then
      raise exception 'The % session already has attendance. Clear its attendance first, then cancel it.',
        to_char(old.session_date, 'Dy DD Mon');
    end if;
    return new;
  end if;
  if exists (select 1 from public.attendance where session_id = old.id)
     and exists (select 1 from public.groups where id = old.group_id) then
    raise exception 'The % session already has attendance. Clear its attendance first.',
      to_char(old.session_date, 'Dy DD Mon');
  end if;
  return old;
end;
$$;

create trigger sessions_protect_marked
  before update of status or delete on public.sessions
  for each row execute function public.protect_marked_sessions();

-- ---------- Taking attendance -----------------------------------------

-- The list for one session: every swimmer who was in the group that day,
-- with their mark if there is one. Coaches only.
create function public.session_roster(p_session_id uuid)
returns table (
  swimmer_id     uuid,
  first_name     text,
  last_name      text,
  birth_date     date,
  status         text,   -- empty = not marked yet
  excuse_reason  text,
  note           text,
  marked_at      timestamptz,
  marked_by_name text
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_session public.sessions;
begin
  perform public.require_signed_in();
  select * into v_session from public.sessions where id = p_session_id;
  if v_session.id is null then
    raise exception 'That session no longer exists.';
  end if;
  if not (public.is_coach(v_session.club_id) or public.is_superadmin()) then
    raise exception 'Only coaches can see the attendance list.' using errcode = '42501';
  end if;

  return query
  select s.id, s.first_name, s.last_name, s.birth_date,
         a.status::text, a.excuse_reason::text, a.note, a.marked_at,
         nullif(p.full_name, '')
  from public.swimmers s
  left join public.attendance a on a.session_id = p_session_id and a.swimmer_id = s.id
  left join public.profiles p on p.id = a.marked_by
  where s.club_id = v_session.club_id
    and (public.swimmer_group_on(s.id, v_session.session_date) = v_session.group_id
         or a.id is not null)
  order by s.last_name, s.first_name;
end;
$$;

-- Saves marks for one session. p_marks is a list like
--   [{"swimmer_id": "...", "status": "excused", "excuse_reason": "medical",
--     "note": "fever"}, ...]
-- Marks for other swimmers in the session are left as they are.
-- Returns how many marks were saved.
create function public.save_attendance(p_session_id uuid, p_marks jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_session public.sessions := public.require_attendance_taker(p_session_id);
  v_mark jsonb;
  v_swimmer uuid;
  v_status public.attendance_status;
  v_reason public.excuse_reason;
  v_count integer := 0;
begin
  if p_marks is null or jsonb_typeof(p_marks) <> 'array' then
    raise exception 'Nothing to save.';
  end if;
  for v_mark in select * from jsonb_array_elements(p_marks) loop
    v_swimmer := (v_mark ->> 'swimmer_id')::uuid;
    v_status := (v_mark ->> 'status')::public.attendance_status;
    v_reason := nullif(v_mark ->> 'excuse_reason', '')::public.excuse_reason;
    if v_status = 'excused' and v_reason is null then
      raise exception 'Pick a reason (Medical, School or Family) for every Excused swimmer.';
    end if;
    if v_status <> 'excused' then
      v_reason := null;
    end if;
    if public.swimmer_group_on(v_swimmer, v_session.session_date) is distinct from v_session.group_id
       and not exists (select 1 from public.attendance
                       where session_id = p_session_id and swimmer_id = v_swimmer) then
      raise exception 'A swimmer on this list wasn''t in this group on that day.';
    end if;

    insert into public.attendance
      (club_id, session_id, swimmer_id, status, excuse_reason, note, marked_by, marked_at)
    values
      (v_session.club_id, p_session_id, v_swimmer, v_status, v_reason,
       nullif(trim(v_mark ->> 'note'), ''), auth.uid(), now())
    on conflict (session_id, swimmer_id) do update
      set status = excluded.status,
          excuse_reason = excluded.excuse_reason,
          note = excluded.note,
          marked_by = excluded.marked_by,
          marked_at = excluded.marked_at
      where attendance.status is distinct from excluded.status
         or attendance.excuse_reason is distinct from excluded.excuse_reason
         or attendance.note is distinct from excluded.note;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Removes every mark from one session (for example before cancelling it).
-- Returns how many marks were removed.
create function public.clear_attendance(p_session_id uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_session public.sessions;
  v_count integer;
begin
  -- Allowed even for a cancelled session, so old marks can be removed.
  perform public.require_signed_in();
  select * into v_session from public.sessions where id = p_session_id;
  if v_session.id is null then
    raise exception 'That session no longer exists.';
  end if;
  if v_session.status = 'scheduled' then
    perform public.require_attendance_taker(p_session_id);
  elsif not public.is_coach(v_session.club_id) then
    raise exception 'Only coaches can change attendance.' using errcode = '42501';
  end if;
  delete from public.attendance where session_id = p_session_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------- Overviews -------------------------------------------------

-- The club's sessions between two dates (at most 62 days) with how many
-- swimmers were in the group that day and how many are marked. Used by the coach Today screen. Coaches only.
create function public.club_attendance_overview(p_club_id uuid, p_from date, p_to date)
returns table (
  session_id     uuid,
  group_id       uuid,
  group_name     text,
  group_level    integer,
  group_colour   text,
  session_date   date,
  start_time     time,
  end_time       time,
  label          text,
  venue          text,
  status         text,
  cancel_reason  text,
  swimmers       integer,
  marked         integer,
  last_marked_at timestamptz,
  last_marked_by text
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.require_signed_in();
  if not (public.is_coach(p_club_id) or public.is_superadmin()) then
    raise exception 'Only coaches can see this.' using errcode = '42501';
  end if;
  if p_to < p_from or p_to - p_from > 62 then
    raise exception 'Pick a range of up to 62 days.';
  end if;

  return query
  select s.id, g.id, g.name, g.level, g.colour, s.session_date, s.start_time, s.end_time,
         s.label, s.venue, s.status::text,
         coalesce(s.cancel_reason, r.title,
                  case r.kind when 'break' then 'Break' when 'rest_day' then 'Rest day' end),
         n.swimmers::integer, coalesce(a.marked, 0)::integer, a.last_at, nullif(p.full_name, '')
  from public.sessions s
  join public.groups g on g.id = s.group_id
  left join public.rest_days r on r.id = s.rest_day_id
  left join lateral (
    select count(*) as marked, max(x.marked_at) as last_at,
           (array_agg(x.marked_by order by x.marked_at desc))[1] as last_by
    from public.attendance x where x.session_id = s.id
  ) a on true
  left join lateral (
    select count(*) as swimmers from public.swimmers sw
    where sw.club_id = s.club_id
      and public.swimmer_group_on(sw.id, s.session_date) = s.group_id
  ) n on true
  left join public.profiles p on p.id = a.last_by
  where s.club_id = p_club_id
    and s.session_date between p_from and p_to
  order by s.session_date, s.start_time, g.level desc, g.name;
end;
$$;

-- One swimmer's marks between two dates (at most 366 days), newest first.
-- For the swimmer, their parents and their coaches. Coach notes are
-- included only for coaches.
create function public.swimmer_attendance(p_swimmer_id uuid, p_from date, p_to date)
returns table (
  session_id     uuid,
  session_date   date,
  start_time     time,
  end_time       time,
  label          text,
  group_name     text,
  status         text,
  excuse_reason  text,
  note           text
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_club uuid;
  v_coach boolean;
begin
  perform public.require_signed_in();
  select club_id into v_club from public.swimmers where id = p_swimmer_id;
  if v_club is null or not (public.can_see_swimmer(p_swimmer_id) or public.is_superadmin()) then
    raise exception 'You can''t see this swimmer.' using errcode = '42501';
  end if;
  -- Teammates can see each other's records, but not each other's attendance.
  v_coach := public.is_coach(v_club) or public.is_superadmin();
  if not (v_coach or public.is_self_or_parent_of(p_swimmer_id)) then
    raise exception 'You can only see your own attendance.' using errcode = '42501';
  end if;
  if p_to < p_from or p_to - p_from > 366 then
    raise exception 'Pick a range of up to one year.';
  end if;

  return query
  select s.id, s.session_date, s.start_time, s.end_time, s.label, g.name,
         a.status::text, a.excuse_reason::text,
         case when v_coach then a.note end
  from public.attendance a
  join public.sessions s on s.id = a.session_id
  join public.groups g on g.id = s.group_id
  where a.swimmer_id = p_swimmer_id
    and s.session_date between p_from and p_to
  order by s.session_date desc, s.start_time desc;
end;
$$;

-- ---------- Who may call what -----------------------------------------

revoke execute on function
  public.swimmer_group_on(uuid, date),
  public.require_attendance_taker(uuid),
  public.log_attendance_change(),
  public.protect_marked_sessions()
from public, anon, authenticated;

grant execute on function
  public.attendance_points(public.attendance_status),
  public.session_roster(uuid),
  public.save_attendance(uuid, jsonb),
  public.clear_attendance(uuid),
  public.club_attendance_overview(uuid, date, date),
  public.swimmer_attendance(uuid, date, date)
to authenticated;
