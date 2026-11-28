-- =====================================================================
-- SwimBase update: swim times and personal bests
-- =====================================================================
-- Plain-English summary:
--   * Coaches (head coach and assistants) add a swimmer's time by hand:
--     course (LCM or SCM), event (e.g. 100 Free), the time, the meet name
--     and the date. Every PB shows Time, Meet and Date, so the meet name
--     and date are required.
--   * Every swim is kept. A swimmer's personal best in an event is simply
--     their fastest swim in it, so PBs update by themselves when a time is
--     added, changed or deleted.
--   * Coaches can fix or delete a time. Each change is kept in a history
--     list with who made it and when, and the old values.
--   * Who sees times: coaches see their club's; swimmers see their own
--     and their teammates'; parents see only their own children's. The
--     superadmin can read them but not change them.
--   * Push notifications come in a later update. For now each new time is
--     written to result_notifications (with whether it was a new PB),
--     ready for the notification sender.
--   * Reading Hy-Tek PDFs and Team Records are later updates; they will
--     build on this same table.
--
-- Run this once in the Supabase SQL Editor.
-- =====================================================================

create type public.swim_stroke as enum ('free', 'back', 'breast', 'fly', 'im');

-- The events a time can be entered for (the list agreed in the spec):
-- Free 50 to 1500; Back, Breast and Fly 50 to 200; IM 100 (SCM only),
-- 200 and 400.
create function public.is_swim_event(p_stroke public.swim_stroke, p_distance integer, p_course public.pool_course)
returns boolean language sql immutable as $$
  select case p_stroke
    when 'free' then p_distance in (50, 100, 200, 400, 800, 1500)
    when 'im'   then p_distance in (200, 400) or (p_distance = 100 and p_course = 'scm')
    else p_distance in (50, 100, 200)
  end
$$;

-- ---------- Tables ----------------------------------------------------

create table public.swim_results (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null,
  swimmer_id  uuid not null,
  course      public.pool_course not null,
  stroke      public.swim_stroke not null,
  distance    integer not null,
  -- The time in hundredths of a second: 1:05.42 is stored as 6542.
  time_cs     integer not null check (time_cs > 0 and time_cs < 360000),
  meet_name   text not null check (length(trim(meet_name)) > 0),
  swim_date   date not null,
  -- The meet in the club's Events, when the coach picked one.
  event_id    uuid references public.events (id) on delete set null,
  -- 'manual' = typed in by a coach. PDF imports come later.
  source      text not null default 'manual' check (source in ('manual', 'import')),
  entered_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  edited_by   uuid references auth.users (id) on delete set null,
  edited_at   timestamptz,
  check (public.is_swim_event(stroke, distance, course)),
  foreign key (swimmer_id, club_id) references public.swimmers (id, club_id) on delete cascade
);
create index swim_results_swimmer_idx on public.swim_results (swimmer_id, course, stroke, distance, time_cs);
create index swim_results_club_event_idx on public.swim_results (club_id, course, stroke, distance, time_cs);

-- Every change to a time, with the values before the change.
create table public.swim_result_changes (
  id          bigint generated always as identity primary key,
  club_id     uuid not null references public.clubs (id) on delete cascade,
  result_id   uuid not null,  -- kept even after the time is deleted
  swimmer_id  uuid not null,
  action      text not null check (action in ('edited', 'deleted')),
  old_values  jsonb not null,
  changed_by  uuid references auth.users (id) on delete set null,
  changed_at  timestamptz not null default now()
);
create index swim_result_changes_result_idx on public.swim_result_changes (result_id, changed_at);

-- The waiting list for "new results" push notifications. Nobody reads
-- this from the app; the notification sender will group the rows by
-- swimmer and meet, send one alert each, and fill in sent_at.
create table public.result_notifications (
  id          bigint generated always as identity primary key,
  club_id     uuid not null references public.clubs (id) on delete cascade,
  swimmer_id  uuid not null,
  result_id   uuid not null references public.swim_results (id) on delete cascade,
  meet_name   text not null,
  is_pb       boolean not null,
  created_at  timestamptz not null default now(),
  sent_at     timestamptz
);
create index result_notifications_unsent_idx on public.result_notifications (created_at) where sent_at is null;

-- Keeps the history whenever a time is changed or deleted.
create function public.log_swim_result_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Nothing to keep when the whole club is being removed.
  if not exists (select 1 from public.clubs where id = old.club_id) then
    return null;
  end if;
  insert into public.swim_result_changes (club_id, result_id, swimmer_id, action, old_values, changed_by)
  values (old.club_id, old.id, old.swimmer_id,
          case when tg_op = 'DELETE' then 'deleted' else 'edited' end,
          to_jsonb(old) - 'club_id' - 'swimmer_id' - 'id', auth.uid());
  return null;
end;
$$;

create trigger swim_results_log_change
  after update or delete on public.swim_results
  for each row execute function public.log_swim_result_change();

-- ---------- Privacy rules ---------------------------------------------

alter table public.swim_results         enable row level security;
alter table public.swim_result_changes  enable row level security;
alter table public.result_notifications enable row level security;

-- can_see_swimmer: coaches and swimmers of the club (teammates), and
-- parents of that swimmer only.
create policy "See times of swimmers you can see" on public.swim_results
  for select to authenticated using (public.can_see_swimmer(swimmer_id) or public.is_superadmin());

create policy "Coaches see the change history" on public.swim_result_changes
  for select to authenticated using (public.is_coach(club_id) or public.is_superadmin());
-- result_notifications has no policy: the app can't read it.

-- Reading only. Every change goes through the functions below.
revoke all on public.swim_results, public.swim_result_changes, public.result_notifications from anon;
revoke all on public.result_notifications from authenticated;
revoke insert, update, delete on public.swim_results, public.swim_result_changes from authenticated;
grant select on public.swim_results, public.swim_result_changes to authenticated;

-- ---------- Adding, changing and deleting -----------------------------

-- Adds a time (p_result_id empty) or changes one. p_time_cs is the time
-- in hundredths. Returns the time's id.
create function public.save_swim_result(
  p_result_id  uuid,
  p_swimmer_id uuid,
  p_course     public.pool_course,
  p_stroke     public.swim_stroke,
  p_distance   integer,
  p_time_cs    integer,
  p_meet_name  text,
  p_swim_date  date,
  p_event_id   uuid default null
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_swimmer public.swimmers;
  v_old public.swim_results;
  v_id uuid;
  v_best integer;
begin
  perform public.require_signed_in();
  select * into v_swimmer from public.swimmers where id = p_swimmer_id;
  if v_swimmer.id is null or not public.is_coach(v_swimmer.club_id) then
    raise exception 'Only coaches of this swimmer''s club can add or change times.' using errcode = '42501';
  end if;
  if p_course is null or p_stroke is null or p_distance is null then
    raise exception 'Pick the course and the event.';
  end if;
  if not public.is_swim_event(p_stroke, p_distance, p_course) then
    raise exception 'That event isn''t swum in this course.';
  end if;
  if p_time_cs is null or p_time_cs <= 0 or p_time_cs >= 360000 then
    raise exception 'Type the time, like 1:05.42.';
  end if;
  if nullif(trim(p_meet_name), '') is null then
    raise exception 'Type the meet name.';
  end if;
  if p_swim_date is null then
    raise exception 'Pick the date of the swim.';
  end if;
  if p_swim_date > public.club_today(v_swimmer.club_id) then
    raise exception 'The date can''t be in the future.';
  end if;
  if p_swim_date < v_swimmer.birth_date then
    raise exception 'The date is before the swimmer was born.';
  end if;
  if p_event_id is not null
     and not exists (select 1 from public.events where id = p_event_id and club_id = v_swimmer.club_id) then
    raise exception 'Pick a meet from this club.';
  end if;

  if p_result_id is null then
    -- Their best in this event before this swim (null = first swim).
    select min(time_cs) into v_best from public.swim_results
     where swimmer_id = p_swimmer_id and course = p_course and stroke = p_stroke and distance = p_distance;

    insert into public.swim_results
      (club_id, swimmer_id, course, stroke, distance, time_cs, meet_name, swim_date, event_id, entered_by)
    values
      (v_swimmer.club_id, p_swimmer_id, p_course, p_stroke, p_distance, p_time_cs,
       trim(p_meet_name), p_swim_date, p_event_id, auth.uid())
    returning id into v_id;

    insert into public.result_notifications (club_id, swimmer_id, result_id, meet_name, is_pb)
    values (v_swimmer.club_id, p_swimmer_id, v_id, trim(p_meet_name), v_best is null or p_time_cs < v_best);
  else
    select * into v_old from public.swim_results where id = p_result_id for update;
    if v_old.id is null or v_old.swimmer_id <> p_swimmer_id then
      raise exception 'That time no longer exists.';
    end if;
    -- Editing an old time never sends a notification.
    update public.swim_results set
      course = p_course, stroke = p_stroke, distance = p_distance, time_cs = p_time_cs,
      meet_name = trim(p_meet_name), swim_date = p_swim_date, event_id = p_event_id,
      edited_by = auth.uid(), edited_at = now()
    where id = p_result_id;
    v_id := p_result_id;
  end if;
  return v_id;
end;
$$;

create function public.delete_swim_result(p_result_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_result public.swim_results;
begin
  perform public.require_signed_in();
  select * into v_result from public.swim_results where id = p_result_id;
  if v_result.id is null then
    raise exception 'That time no longer exists.';
  end if;
  if not public.is_coach(v_result.club_id) then
    raise exception 'Only coaches can delete times.' using errcode = '42501';
  end if;
  delete from public.swim_results where id = p_result_id;
end;
$$;

-- ---------- Who may call what -----------------------------------------

revoke execute on function public.log_swim_result_change() from public, anon, authenticated;

grant execute on function
  public.save_swim_result(uuid, uuid, public.pool_course, public.swim_stroke, integer, integer, text, date, uuid),
  public.delete_swim_result(uuid),
  public.is_swim_event(public.swim_stroke, integer, public.pool_course)
to authenticated;
