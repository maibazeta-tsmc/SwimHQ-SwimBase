-- =====================================================================
-- SwimBase update: upcoming events (swim meets, socials and more)
-- =====================================================================
-- Plain-English summary:
--   * Coaches (head coach and assistants) add events for their club: a
--     title, a type (Meet, Social or Other), first and last day, an
--     optional start and end time (no time = all day), a place, the pool
--     course for meets (LCM or SCM), notes and a web link.
--   * Each event is for the whole club or for the groups the coach picks.
--   * Swimmers and parents see the events for their group (and whole-club
--     events) through swimmer_events(). A swimmer follows the group they
--     are in on the event date, including planned moves.
--   * "Cancel training these days" turns the event dates into rest days
--     for the chosen groups, so training doesn't have to be cancelled
--     separately. This needs the same permission as rest days.
--   * Editing an event marks it as updated so families can see it changed.
--   * Push notifications come in a later update. For now every new or
--     changed event that should notify families is written to
--     event_notifications, ready for the notification sender.
--   * The superadmin can read events but not change them.
--
-- Run this once in the Supabase SQL Editor.
-- =====================================================================

create type public.event_kind as enum ('meet', 'social', 'other');
create type public.pool_course as enum ('lcm', 'scm');

-- ---------- Tables ----------------------------------------------------

create table public.events (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references public.clubs (id) on delete cascade,
  title       text not null check (length(trim(title)) > 0),
  kind        public.event_kind not null default 'meet',
  start_date  date not null,
  end_date    date not null,
  start_time  time,          -- empty = all day
  end_time    time,
  venue       text,
  course      public.pool_course,  -- meets only
  notes       text,
  link        text,
  -- true = for everyone in the club; false = only the groups in event_groups.
  whole_club  boolean not null default true,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_by  uuid references auth.users (id) on delete set null,
  updated_at  timestamptz,   -- empty until the event is edited
  check (end_date >= start_date),
  check (course is null or kind = 'meet'),
  check ((start_time is null) = (end_time is null)),
  check (start_time is null or end_date > start_date or end_time > start_time),
  check (link is null or link ~* '^https?://'),
  unique (id, club_id)
);
create index events_club_date_idx on public.events (club_id, start_date);

-- The groups an event is for, when it isn't for the whole club.
create table public.event_groups (
  event_id  uuid not null,
  club_id   uuid not null,
  group_id  uuid not null,
  primary key (event_id, group_id),
  foreign key (event_id, club_id) references public.events (id, club_id) on delete cascade,
  foreign key (group_id, club_id) references public.groups (id, club_id) on delete cascade
);
create index event_groups_group_idx on public.event_groups (group_id);

-- Rest days an event made with "Cancel training these days".
alter table public.rest_days
  add column event_id uuid references public.events (id) on delete set null;
create index rest_days_event_idx on public.rest_days (event_id);

-- The waiting list for push notifications (the hook for a later update).
-- Nobody reads this from the app; the notification sender will send each
-- row and fill in sent_at.
create table public.event_notifications (
  id          bigint generated always as identity primary key,
  club_id     uuid not null references public.clubs (id) on delete cascade,
  event_id    uuid not null references public.events (id) on delete cascade,
  reason      text not null check (reason in ('new', 'updated')),
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  sent_at     timestamptz
);
create index event_notifications_unsent_idx on public.event_notifications (created_at) where sent_at is null;

-- ---------- Privacy rules ---------------------------------------------

alter table public.events              enable row level security;
alter table public.event_groups        enable row level security;
alter table public.event_notifications enable row level security;

-- Events are not private inside a club, like training schedules.
create policy "Members see events" on public.events
  for select to authenticated using (public.is_club_member(club_id) or public.is_superadmin());
create policy "Members see event groups" on public.event_groups
  for select to authenticated using (public.is_club_member(club_id) or public.is_superadmin());
-- event_notifications has no policy: the app can't read it.

-- Reading only. Every change goes through the functions below.
revoke all on public.events, public.event_groups, public.event_notifications from anon;
revoke all on public.event_notifications from authenticated;
revoke insert, update, delete on public.events, public.event_groups from authenticated;
grant select on public.events, public.event_groups to authenticated;

-- ---------- Helpers ---------------------------------------------------

-- Removes the rest days an event made, bringing back their sessions.
-- Uses remove_rest_day, so it needs the same permission.
create function public.remove_event_rest_days(p_event_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_rest uuid;
begin
  for v_rest in select id from public.rest_days where event_id = p_event_id loop
    begin
      perform public.remove_rest_day(v_rest);
    exception when insufficient_privilege then
      raise exception 'This event also cancelled training, and you can''t change those groups'' schedules. Ask your head coach.'
        using errcode = '42501';
    end;
  end loop;
end;
$$;

-- ---------- Adding, changing and deleting -----------------------------

-- Adds a new event (p_event_id empty) or changes one. p_group_ids empty =
-- whole club. Returns the event's id.
create function public.save_event(
  p_event_id        uuid,
  p_club_id         uuid,
  p_title           text,
  p_kind            public.event_kind,
  p_start_date      date,
  p_end_date        date,
  p_start_time      time default null,
  p_end_time        time default null,
  p_venue           text default null,
  p_course          public.pool_course default null,
  p_notes           text default null,
  p_link            text default null,
  p_group_ids       uuid[] default null,
  p_cancel_training boolean default false,
  p_notify          boolean default true
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_old public.events;
  v_id uuid;
  v_groups uuid[] := coalesce(p_group_ids, '{}');
  v_old_groups uuid[];
  v_had_rest boolean := false;
  v_link text := nullif(trim(p_link), '');
  v_kind public.event_kind := coalesce(p_kind, 'meet');
begin
  perform public.require_signed_in();
  if not public.is_coach(p_club_id) then
    raise exception 'Only coaches can add or change events.' using errcode = '42501';
  end if;
  if nullif(trim(p_title), '') is null then
    raise exception 'Give the event a title.';
  end if;
  if p_start_date is null or p_end_date is null then
    raise exception 'Pick the first and last day.';
  end if;
  if p_end_date < p_start_date then
    raise exception 'The last day must be on or after the first day.';
  end if;
  if (p_start_time is null) <> (p_end_time is null) then
    raise exception 'Give both a start and an end time, or tick All day.';
  end if;
  if p_start_time is not null and p_end_date = p_start_date and p_end_time <= p_start_time then
    raise exception 'The end time must be after the start time.';
  end if;
  if v_link is not null and v_link !~* '^https?://' then
    v_link := 'https://' || v_link;
  end if;
  if exists (
    select 1 from unnest(v_groups) g
    where not exists (select 1 from public.groups where id = g and club_id = p_club_id and archived_at is null)
  ) then
    raise exception 'Pick groups from this club.';
  end if;

  if p_event_id is null then
    insert into public.events
      (club_id, title, kind, start_date, end_date, start_time, end_time, venue, course,
       notes, link, whole_club, created_by)
    values
      (p_club_id, trim(p_title), v_kind, p_start_date, p_end_date, p_start_time, p_end_time,
       nullif(trim(p_venue), ''), case when v_kind = 'meet' then p_course end,
       nullif(trim(p_notes), ''), v_link, cardinality(v_groups) = 0, auth.uid())
    returning id into v_id;
  else
    select * into v_old from public.events where id = p_event_id for update;
    if v_old.id is null or v_old.club_id <> p_club_id then
      raise exception 'That event no longer exists.';
    end if;
    v_id := v_old.id;
    select coalesce(array_agg(group_id order by group_id), '{}') into v_old_groups
      from public.event_groups where event_id = v_id;
    v_had_rest := exists (select 1 from public.rest_days where event_id = v_id);

    -- The rest days follow the event: redo them only if the days, groups
    -- or the tick changed, so a small edit doesn't need schedule rights.
    if v_had_rest and (not coalesce(p_cancel_training, false)
                       or v_old.start_date <> p_start_date or v_old.end_date <> p_end_date
                       or v_old_groups <> (select coalesce(array_agg(distinct g order by g), '{}') from unnest(v_groups) g)) then
      perform public.remove_event_rest_days(v_id);
      v_had_rest := false;
    elsif v_had_rest then
      update public.rest_days set title = trim(p_title) where event_id = v_id;
    end if;

    update public.events set
      title = trim(p_title), kind = v_kind, start_date = p_start_date, end_date = p_end_date,
      start_time = p_start_time, end_time = p_end_time, venue = nullif(trim(p_venue), ''),
      course = case when v_kind = 'meet' then p_course end, notes = nullif(trim(p_notes), ''),
      link = v_link, whole_club = cardinality(v_groups) = 0,
      updated_by = auth.uid(), updated_at = now()
    where id = v_id;
    delete from public.event_groups where event_id = v_id;
  end if;

  insert into public.event_groups (event_id, club_id, group_id)
  select distinct v_id, p_club_id, g from unnest(v_groups) g;

  if coalesce(p_cancel_training, false) and not v_had_rest then
    perform public.add_rest_days(p_club_id, case when cardinality(v_groups) = 0 then null else v_groups end,
                                 p_start_date, p_end_date, 'rest_day', trim(p_title));
    -- add_rest_days doesn't return the new rest days. Everything written in
    -- this call shares the same now(), which picks them out.
    update public.rest_days set event_id = v_id
     where club_id = p_club_id and created_by = auth.uid() and created_at = now() and event_id is null;
  end if;

  if coalesce(p_notify, true) then
    insert into public.event_notifications (club_id, event_id, reason, created_by)
    values (p_club_id, v_id, case when p_event_id is null then 'new' else 'updated' end, auth.uid());
  end if;
  return v_id;
end;
$$;

-- Deletes an event. Training it cancelled comes back.
create function public.delete_event(p_event_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event public.events;
begin
  perform public.require_signed_in();
  select * into v_event from public.events where id = p_event_id;
  if v_event.id is null then
    raise exception 'That event no longer exists.';
  end if;
  if not public.is_coach(v_event.club_id) then
    raise exception 'Only coaches can delete events.' using errcode = '42501';
  end if;
  perform public.remove_event_rest_days(p_event_id);
  delete from public.events where id = p_event_id;
end;
$$;

-- ---------- A swimmer's events ----------------------------------------

-- The events for one swimmer that end on or after p_from and start on or
-- before p_to (at most 366 days): whole-club events, and events for the
-- group the swimmer is in on the event day (or today, for an event
-- already under way).
create function public.swimmer_events(p_swimmer_id uuid, p_from date, p_to date)
returns table (
  event_id    uuid,
  title       text,
  kind        text,
  start_date  date,
  end_date    date,
  start_time  time,
  end_time    time,
  venue       text,
  course      text,
  notes       text,
  link        text,
  updated_at  timestamptz
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_club uuid;
begin
  perform public.require_signed_in();
  select club_id into v_club from public.swimmers where id = p_swimmer_id;
  if v_club is null or not (public.can_see_swimmer(p_swimmer_id) or public.is_superadmin()) then
    raise exception 'You can''t see this swimmer.' using errcode = '42501';
  end if;
  if p_to < p_from or p_to - p_from > 366 then
    raise exception 'Pick a range of up to one year.';
  end if;

  return query
  select e.id, e.title, e.kind::text, e.start_date, e.end_date, e.start_time, e.end_time,
         e.venue, e.course::text, e.notes, e.link, e.updated_at
  from public.events e
  where e.club_id = v_club
    and e.end_date >= p_from
    and e.start_date <= p_to
    and (e.whole_club or exists (
          select 1 from public.event_groups eg
          where eg.event_id = e.id
            and eg.group_id = public.swimmer_group_on(
                  p_swimmer_id, greatest(e.start_date, public.club_today(v_club)))))
  order by e.start_date, e.start_time nulls first, e.title;
end;
$$;

-- ---------- Who may call what -----------------------------------------

revoke execute on function public.remove_event_rest_days(uuid) from public, anon, authenticated;

grant execute on function
  public.save_event(uuid, uuid, text, public.event_kind, date, date, time, time, text,
                    public.pool_course, text, text, uuid[], boolean, boolean),
  public.delete_event(uuid),
  public.swimmer_events(uuid, date, date)
to authenticated;
