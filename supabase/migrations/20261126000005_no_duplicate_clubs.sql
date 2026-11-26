-- =====================================================================
-- SwimBase fix: stop duplicate clubs
-- =====================================================================
-- Plain-English summary:
--   * Two clubs in the same country can't have the same name (capital
--     letters and extra spaces don't count as different).
--   * A person can only have one club waiting for approval at a time.
--   Both give a clear message in the app instead of creating a copy.
--
--   Run this AFTER removing any duplicate clubs, or it will stop with
--   "could not create unique index".
-- =====================================================================

create unique index clubs_unique_name_per_country
  on public.clubs (lower(regexp_replace(trim(name), '\s+', ' ', 'g')), country);

create or replace function public.register_club(p_name text, p_country text default 'PH', p_timezone text default 'Asia/Manila')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := public.require_signed_in();
  v_name text := regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_club uuid;
begin
  if v_name = '' then
    raise exception 'Please enter your club''s name.';
  end if;

  -- One club waiting for approval per person.
  if exists (
    select 1 from public.club_members m join public.clubs c on c.id = m.club_id
    where m.user_id = v_user and m.role = 'head_coach' and c.status = 'pending'
  ) then
    raise exception 'You already have a club waiting for approval. Please wait until it is approved before registering another.';
  end if;

  if exists (
    select 1 from public.clubs
    where lower(regexp_replace(trim(name), '\s+', ' ', 'g')) = lower(v_name)
      and country = coalesce(p_country, 'PH')
  ) then
    raise exception 'A club called "%" is already registered. If it is yours, it is already in your list.', v_name;
  end if;

  begin
    insert into public.clubs (name, country, timezone, created_by)
    values (v_name, coalesce(p_country, 'PH'), coalesce(p_timezone, 'Asia/Manila'), v_user)
    returning id into v_club;
  exception when unique_violation then
    -- Two taps at the same moment: the second one lands here.
    raise exception 'A club called "%" is already registered. If it is yours, it is already in your list.', v_name;
  end;

  insert into public.club_members (club_id, user_id, role)
  values (v_club, v_user, 'head_coach');

  perform public.write_audit(v_club, 'club_registered', jsonb_build_object('name', v_name));
  return v_club;
end;
$$;
