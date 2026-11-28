-- =====================================================================
-- SwimBase update: attendance summary for the coach dashboard
-- =====================================================================
-- Plain-English summary:
--   * Adds one read-only function, club_attendance_summary(), that the
--     coach's Today screen uses to show attendance rates for a period
--     (this week, this month or this season).
--   * For each swimmer it counts their marks (Present, Late, Early-Up,
--     DNF, Absent, Excused), split by the group the session belonged to.
--     So a swimmer who moved up counts towards each group for the
--     sessions they swam there.
--   * The app works out the percentages with the usual rule: Present = 1,
--     Late / Early-Up / DNF = half, Absent = 0, Excused not counted.
--   * Coaches of the club only (and the superadmin, read only). Nothing
--     in the database changes; no tables are added.
--
-- Run this once in the Supabase SQL Editor.
-- =====================================================================

create function public.club_attendance_summary(p_club_id uuid, p_from date, p_to date)
returns table (
  swimmer_id        uuid,
  first_name        text,
  last_name         text,
  swimmer_status    text,
  current_group_id  uuid,
  current_group_name text,
  current_group_level integer,
  current_group_colour text,
  group_id          uuid,   -- the group the sessions belonged to
  group_name        text,
  group_level       integer,
  group_colour      text,
  present           integer,
  late              integer,
  early_up          integer,
  dnf               integer,
  absent            integer,
  excused           integer
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.require_signed_in();
  if not (public.is_coach(p_club_id) or public.is_superadmin()) then
    raise exception 'Only coaches can see this.' using errcode = '42501';
  end if;
  if p_to < p_from or p_to - p_from > 366 then
    raise exception 'Pick a range of up to one year.';
  end if;

  return query
  select sw.id, sw.first_name, sw.last_name, sw.status::text, sw.current_group_id,
         cg.name, cg.level, cg.colour,
         g.id, g.name, g.level, g.colour,
         (count(*) filter (where a.status = 'present'))::integer,
         (count(*) filter (where a.status = 'late'))::integer,
         (count(*) filter (where a.status = 'early_up'))::integer,
         (count(*) filter (where a.status = 'dnf'))::integer,
         (count(*) filter (where a.status = 'absent'))::integer,
         (count(*) filter (where a.status = 'excused'))::integer
  from public.attendance a
  join public.sessions s on s.id = a.session_id
  join public.groups g on g.id = s.group_id
  join public.swimmers sw on sw.id = a.swimmer_id
  left join public.groups cg on cg.id = sw.current_group_id
  where a.club_id = p_club_id
    and s.session_date between p_from and p_to
  group by sw.id, g.id, cg.id
  order by g.level desc, g.name, sw.last_name, sw.first_name;
end;
$$;

grant execute on function public.club_attendance_summary(uuid, date, date) to authenticated;
