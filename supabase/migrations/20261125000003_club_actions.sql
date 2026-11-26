-- =====================================================================
-- SwimBase foundation, part 3 of 3: actions the app can ask for
-- =====================================================================
-- Plain-English summary:
--   Some actions need several checks or touch several tables at once, so
--   the app calls these functions instead of editing tables directly:
--
--   register_club            a head coach registers a new club (pending)
--   approve_club             the superadmin approves a pending club
--   set_club_status          the superadmin suspends or re-approves a club
--   transfer_head_coach      head coach (or superadmin) hands over the role
--   set_coach_permissions    head coach turns the two assistant switches on/off
--   create_invite_code       coach makes a one-time code (coach/swimmer/parent)
--   redeem_invite_code       a signed-in person uses a code to join
--   move_swimmers            move one or several swimmers to another group
--   cancel_scheduled_move    cancel a move that hasn't happened yet
--   mark_swimmer_left        swimmer leaves the club (history is kept)
--   apply_scheduled_moves    run daily to apply moves whose date has come
-- =====================================================================

-- ---------- Small helpers ---------------------------------------------

create function public.write_audit(p_club_id uuid, p_action text, p_details jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = public as $$
  insert into public.audit_log (club_id, actor_id, action, details)
  values (p_club_id, auth.uid(), p_action, coalesce(p_details, '{}'::jsonb))
$$;
revoke execute on function public.write_audit(uuid, text, jsonb) from public, anon, authenticated;

-- "Today" in the club's own timezone (Manila by default).
create function public.club_today(p_club_id uuid)
returns date language sql stable security definer set search_path = public as $$
  select (now() at time zone coalesce((select timezone from public.clubs where id = p_club_id), 'Asia/Manila'))::date
$$;

create function public.require_signed_in()
returns uuid language plpgsql stable as $$
begin
  if auth.uid() is null then
    raise exception 'Please sign in first.' using errcode = '28000';
  end if;
  return auth.uid();
end;
$$;

-- ---------- Clubs -----------------------------------------------------

create function public.register_club(p_name text, p_country text default 'PH', p_timezone text default 'Asia/Manila')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := public.require_signed_in();
  v_club uuid;
begin
  insert into public.clubs (name, country, timezone, created_by)
  values (trim(p_name), coalesce(p_country, 'PH'), coalesce(p_timezone, 'Asia/Manila'), v_user)
  returning id into v_club;

  insert into public.club_members (club_id, user_id, role)
  values (v_club, v_user, 'head_coach');

  perform public.write_audit(v_club, 'club_registered', jsonb_build_object('name', p_name));
  return v_club;
end;
$$;

create function public.approve_club(p_club_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_signed_in();
  if not public.is_superadmin() then
    raise exception 'Only the app owner can approve clubs.' using errcode = '42501';
  end if;
  update public.clubs
     set status = 'approved', approved_at = now(), approved_by = auth.uid()
   where id = p_club_id;
  if not found then
    raise exception 'Club not found.';
  end if;
  perform public.write_audit(p_club_id, 'club_approved');
end;
$$;

create function public.set_club_status(p_club_id uuid, p_status public.club_status)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_signed_in();
  if not public.is_superadmin() then
    raise exception 'Only the app owner can change a club''s status.' using errcode = '42501';
  end if;
  update public.clubs set status = p_status where id = p_club_id;
  if not found then
    raise exception 'Club not found.';
  end if;
  perform public.write_audit(p_club_id, 'club_status_changed', jsonb_build_object('status', p_status));
end;
$$;

-- ---------- Coaches ---------------------------------------------------

-- Hands the head coach role to an assistant coach of the same club. The old
-- head coach stays on as an assistant coach. Allowed for the current head
-- coach and for the superadmin.
create function public.transfer_head_coach(p_club_id uuid, p_new_head_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_old uuid;
begin
  perform public.require_signed_in();
  if not (public.is_head_coach(p_club_id) or public.is_superadmin()) then
    raise exception 'Only the head coach or the app owner can do this.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.club_members
                 where club_id = p_club_id and user_id = p_new_head_user_id and role = 'assistant_coach') then
    raise exception 'The new head coach must already be a coach in this club.';
  end if;

  select user_id into v_old from public.club_members
   where club_id = p_club_id and role = 'head_coach' for update;

  -- Old head coach becomes an assistant (with no extra switches).
  update public.club_members set role = 'assistant_coach'
   where club_id = p_club_id and role = 'head_coach';
  update public.club_members
     set role = 'head_coach', can_create_groups = false, can_move_swimmers = false
   where club_id = p_club_id and user_id = p_new_head_user_id and role = 'assistant_coach';

  perform public.write_audit(p_club_id, 'head_coach_transferred',
    jsonb_build_object('from', v_old, 'to', p_new_head_user_id, 'by_superadmin', public.is_superadmin()));
end;
$$;

create function public.set_coach_permissions(p_member_id uuid, p_can_create_groups boolean, p_can_move_swimmers boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_member public.club_members;
begin
  perform public.require_signed_in();
  select * into v_member from public.club_members where id = p_member_id;
  if v_member.id is null or not public.is_head_coach(v_member.club_id) then
    raise exception 'Only the head coach can change coach permissions.' using errcode = '42501';
  end if;
  if v_member.role <> 'assistant_coach' then
    raise exception 'Permissions can only be set for assistant coaches.';
  end if;
  update public.club_members
     set can_create_groups = p_can_create_groups, can_move_swimmers = p_can_move_swimmers
   where id = p_member_id;
  perform public.write_audit(v_member.club_id, 'coach_permissions_changed',
    jsonb_build_object('coach', v_member.user_id,
                       'can_create_groups', p_can_create_groups,
                       'can_move_swimmers', p_can_move_swimmers));
end;
$$;

-- ---------- Invite codes ----------------------------------------------

-- Makes an 8-character code like KX7P-29QD. Letters that look alike
-- (0/O, 1/I/L) are left out so codes are easy to read aloud.
create function public.generate_code()
returns text language plpgsql volatile as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v text := '';
begin
  for i in 1..8 loop
    v := v || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    if i = 4 then v := v || '-'; end if;
  end loop;
  return v;
end;
$$;

-- Coaches create codes. While a club is pending approval, it can invite
-- coaches but not swimmers or parents.
create function public.create_invite_code(p_club_id uuid, p_role public.invite_role, p_swimmer_id uuid default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_code text;
  v_status public.club_status;
begin
  perform public.require_signed_in();
  select status into v_status from public.clubs where id = p_club_id;

  if p_role = 'assistant_coach' then
    if not public.is_head_coach(p_club_id) then
      raise exception 'Only the head coach can invite coaches.' using errcode = '42501';
    end if;
    if p_swimmer_id is not null then
      raise exception 'A coach invite is not tied to a swimmer.';
    end if;
  else
    if not public.is_coach(p_club_id) then
      raise exception 'Only coaches can create invite codes.' using errcode = '42501';
    end if;
    if v_status <> 'approved' then
      raise exception 'Your club is waiting for approval. You can invite swimmers and parents once it is approved.';
    end if;
    if not exists (select 1 from public.swimmers
                   where id = p_swimmer_id and club_id = p_club_id and status = 'active') then
      raise exception 'Choose an active swimmer from your club.';
    end if;
  end if;

  if v_status = 'suspended' then
    raise exception 'This club is suspended.';
  end if;

  loop
    v_code := public.generate_code();
    exit when not exists (select 1 from public.invite_codes where code = v_code);
  end loop;

  insert into public.invite_codes (club_id, role, swimmer_id, code, created_by)
  values (p_club_id, p_role, p_swimmer_id, v_code, auth.uid());
  return v_code;
end;
$$;

-- The signed-in person enters a code. Returns the club id they joined.
create function public.redeem_invite_code(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := public.require_signed_in();
  v_inv public.invite_codes;
  v_clean text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  if length(v_clean) <> 8 then
    raise exception 'That code doesn''t look right. Codes have 8 letters and numbers.';
  end if;
  v_clean := substr(v_clean, 1, 4) || '-' || substr(v_clean, 5, 4);

  select * into v_inv from public.invite_codes where code = v_clean for update;
  if v_inv.id is null or v_inv.used_at is not null or v_inv.expires_at < now() then
    raise exception 'This code is not valid or has expired. Ask your coach for a new one.';
  end if;
  if (select status from public.clubs where id = v_inv.club_id) = 'suspended' then
    raise exception 'This club is suspended.';
  end if;

  if v_inv.role = 'assistant_coach' then
    if exists (select 1 from public.club_members
               where club_id = v_inv.club_id and user_id = v_user and role in ('head_coach', 'assistant_coach')) then
      raise exception 'You are already a coach in this club.';
    end if;
    insert into public.club_members (club_id, user_id, role)
    values (v_inv.club_id, v_user, 'assistant_coach');

  elsif v_inv.role = 'swimmer' then
    if exists (select 1 from public.swimmers where id = v_inv.swimmer_id and user_id is not null) then
      raise exception 'This swimmer already has a login.';
    end if;
    update public.swimmers set user_id = v_user where id = v_inv.swimmer_id;
    insert into public.club_members (club_id, user_id, role)
    values (v_inv.club_id, v_user, 'swimmer')
    on conflict (club_id, user_id, role) do nothing;

  else -- parent
    if exists (select 1 from public.swimmers where id = v_inv.swimmer_id and user_id = v_user) then
      raise exception 'You can''t link to yourself as a parent.';
    end if;
    insert into public.parent_links (club_id, swimmer_id, parent_user_id)
    values (v_inv.club_id, v_inv.swimmer_id, v_user)
    on conflict (swimmer_id, parent_user_id) do nothing;
    insert into public.club_members (club_id, user_id, role)
    values (v_inv.club_id, v_user, 'parent')
    on conflict (club_id, user_id, role) do nothing;
  end if;

  update public.invite_codes set used_at = now(), used_by = v_user where id = v_inv.id;
  return v_inv.club_id;
end;
$$;

-- ---------- Group moves -----------------------------------------------

-- Works out up / down / sideways from the two groups' levels.
create function public.move_direction_between(p_from uuid, p_to uuid)
returns public.move_direction language sql stable security definer set search_path = public as $$
  select case
    when p_from is null then 'joined'::public.move_direction
    when (select level from public.groups where id = p_to) > (select level from public.groups where id = p_from) then 'up'
    when (select level from public.groups where id = p_to) < (select level from public.groups where id = p_from) then 'down'
    else 'sideways'
  end
$$;

-- Moves one or several swimmers to another group. If the effective date is
-- today or earlier the move happens now; a future date schedules it.
-- Any earlier scheduled move for the same swimmer is cancelled.
-- p_expected_from_group_ids (optional, same order as p_swimmer_ids) protects
-- against two coaches moving the same swimmer at the same moment.
-- Returns the batch id shared by every entry written.
create function public.move_swimmers(
  p_swimmer_ids uuid[],
  p_to_group_id uuid,
  p_effective_date date default null,
  p_reason text default null,
  p_share_reason boolean default false,
  p_notify boolean default true,
  p_expected_from_group_ids uuid[] default null
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_club uuid;
  v_date date;
  v_today date;
  v_batch uuid := gen_random_uuid();
  v_swimmer public.swimmers;
  v_from uuid;
  v_status public.move_status;
  i int;
begin
  perform public.require_signed_in();
  if p_swimmer_ids is null or cardinality(p_swimmer_ids) = 0 then
    raise exception 'Choose at least one swimmer.';
  end if;

  select club_id into v_club from public.groups where id = p_to_group_id and archived_at is null;
  if v_club is null then
    raise exception 'That group doesn''t exist or is archived.';
  end if;
  if not public.can_move_swimmers(v_club) then
    raise exception 'You don''t have permission to move swimmers. Ask your head coach.' using errcode = '42501';
  end if;

  v_today := public.club_today(v_club);
  v_date := coalesce(p_effective_date, v_today);
  v_status := case when v_date <= v_today then 'done' else 'scheduled' end;

  for i in 1 .. cardinality(p_swimmer_ids) loop
    select * into v_swimmer from public.swimmers
     where id = p_swimmer_ids[i] and club_id = v_club and status = 'active'
     for update;
    if v_swimmer.id is null then
      raise exception 'One of the swimmers is not an active swimmer in this club.';
    end if;

    v_from := v_swimmer.current_group_id;
    if p_expected_from_group_ids is not null
       and v_from is distinct from p_expected_from_group_ids[i] then
      raise exception '% % was just moved by another coach. Refresh and try again.',
        v_swimmer.first_name, v_swimmer.last_name using errcode = '40001';
    end if;
    if v_from = p_to_group_id and v_status = 'done' then
      continue; -- already there
    end if;

    -- A new move replaces any pending scheduled move.
    update public.group_moves set status = 'cancelled'
     where swimmer_id = v_swimmer.id and status = 'scheduled';

    insert into public.group_moves
      (club_id, swimmer_id, from_group_id, to_group_id, direction, effective_date,
       reason, share_reason, notify, status, batch_id, moved_by)
    values
      (v_club, v_swimmer.id, v_from, p_to_group_id,
       public.move_direction_between(v_from, p_to_group_id), v_date,
       nullif(trim(p_reason), ''), coalesce(p_share_reason, false), coalesce(p_notify, true),
       v_status, v_batch, auth.uid());

    if v_status = 'done' then
      update public.swimmers set current_group_id = p_to_group_id where id = v_swimmer.id;
    end if;
  end loop;

  return v_batch;
end;
$$;

create function public.cancel_scheduled_move(p_move_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_club uuid;
begin
  perform public.require_signed_in();
  select club_id into v_club from public.group_moves where id = p_move_id and status = 'scheduled';
  if v_club is null then
    raise exception 'There is no scheduled move to cancel.';
  end if;
  if not public.can_move_swimmers(v_club) then
    raise exception 'You don''t have permission to move swimmers.' using errcode = '42501';
  end if;
  update public.group_moves set status = 'cancelled' where id = p_move_id;
end;
$$;

create function public.mark_swimmer_left(p_swimmer_id uuid, p_left_on date default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_swimmer public.swimmers;
begin
  perform public.require_signed_in();
  select * into v_swimmer from public.swimmers where id = p_swimmer_id for update;
  if v_swimmer.id is null or not public.is_coach(v_swimmer.club_id) then
    raise exception 'Only coaches of this swimmer''s club can do this.' using errcode = '42501';
  end if;
  if v_swimmer.status = 'left' then
    return;
  end if;

  update public.group_moves set status = 'cancelled'
   where swimmer_id = p_swimmer_id and status = 'scheduled';
  insert into public.group_moves
    (club_id, swimmer_id, from_group_id, to_group_id, direction, effective_date, notify, moved_by)
  values
    (v_swimmer.club_id, p_swimmer_id, v_swimmer.current_group_id, null, 'left_club',
     coalesce(p_left_on, public.club_today(v_swimmer.club_id)), false, auth.uid());

  update public.swimmers
     set status = 'left', left_on = coalesce(p_left_on, public.club_today(v_swimmer.club_id)),
         current_group_id = null
   where id = p_swimmer_id;

  -- The swimmer's parent links in this club end with them.
  delete from public.parent_links where swimmer_id = p_swimmer_id;
end;
$$;

-- Applies scheduled moves whose date has arrived. Meant to run once a day
-- (set up with Supabase's scheduler in a later phase). Not callable from
-- the app.
create function public.apply_scheduled_moves()
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_count integer := 0;
  m record;
begin
  for m in
    select gm.* from public.group_moves gm
    join public.swimmers s on s.id = gm.swimmer_id
    where gm.status = 'scheduled' and s.status = 'active'
      and gm.effective_date <= public.club_today(gm.club_id)
    order by gm.effective_date, gm.recorded_at
  loop
    update public.swimmers set current_group_id = m.to_group_id where id = m.swimmer_id;
    update public.group_moves set status = 'done' where id = m.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function public.apply_scheduled_moves() from public, anon, authenticated;

-- ---------- Who may call what -----------------------------------------
-- Functions are callable by everyone by default in Postgres. Lock them to
-- signed-in users; each function also does its own permission checks.

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.register_club(text, text, text),
  public.approve_club(uuid),
  public.set_club_status(uuid, public.club_status),
  public.transfer_head_coach(uuid, uuid),
  public.set_coach_permissions(uuid, boolean, boolean),
  public.create_invite_code(uuid, public.invite_role, uuid),
  public.redeem_invite_code(text),
  public.move_swimmers(uuid[], uuid, date, text, boolean, boolean, uuid[]),
  public.cancel_scheduled_move(uuid),
  public.mark_swimmer_left(uuid, date),
  public.is_superadmin(),
  public.age_on(date, date)
to authenticated;

-- The privacy rules in part 2 call these helpers as the signed-in user.
grant execute on function
  public.has_club_role(uuid, public.club_role[]),
  public.is_club_member(uuid),
  public.is_coach(uuid),
  public.is_head_coach(uuid),
  public.can_manage_groups(uuid),
  public.can_move_swimmers(uuid),
  public.is_self_or_parent_of(uuid),
  public.can_see_swimmer(uuid),
  public.club_today(uuid),
  public.require_signed_in(),
  public.move_direction_between(uuid, uuid)
to authenticated;

-- Supabase's auto-generated API would otherwise expose new functions to
-- logged-out visitors in future migrations.
alter default privileges in schema public revoke execute on functions from public, anon;
