-- =====================================================================
-- SwimBase fix: give signed-in users explicit access to the app's tables
-- =====================================================================
-- Plain-English summary:
--   Newer Supabase projects no longer open new tables to the app by
--   default. Without this file, the app can't read the clubs list
--   ("Could not load your clubs"). This file opens exactly the access
--   the app needs. The privacy rules from part 2 still decide which ROWS
--   each person can see or change, so no club can see another's data.
--
--   Safe to run more than once.
-- =====================================================================

grant usage on schema public to authenticated;

-- Reading: the privacy rules filter what each person sees.
grant select on
  public.profiles, public.superadmins, public.clubs, public.club_members,
  public.groups, public.group_coaches, public.swimmers, public.parent_links,
  public.invite_codes, public.group_moves, public.audit_log,
  public.family_group_history
to authenticated;

-- Changing: only the columns and actions the privacy rules allow.
grant update (full_name, phone) on public.profiles to authenticated;
grant update (name, country, timezone) on public.clubs to authenticated;
grant delete on public.club_members to authenticated;
grant insert on public.groups to authenticated;
grant update (name, level, colour, description, archived_at) on public.groups to authenticated;
grant insert, delete on public.group_coaches to authenticated;
grant insert on public.swimmers to authenticated;
grant update (first_name, last_name, birth_date, gender) on public.swimmers to authenticated;
grant delete on public.parent_links to authenticated;
grant delete on public.invite_codes to authenticated;
