-- =====================================================================
-- SwimBase foundation, part 2 of 3: privacy rules (row-level security)
-- =====================================================================
-- Plain-English summary:
--   The database itself decides who can see and change each row, so even
--   a modified copy of the app cannot read another club's data.
--
--   * Nobody sees anything from a club they don't belong to.
--   * The superadmin (Miguel) can READ every club, but cannot change data
--     inside a club. The only things the superadmin can change are a
--     club's approval status and who its head coach is (part 3).
--   * Coaches see everything in their own club.
--   * Swimmers see their teammates (names, birthdays, groups) so they can
--     compare times later.
--   * Parents see only their own linked children.
--   * Sensitive actions go through the functions in part 3 instead of
--     direct edits, so their rules can be checked and logged.
-- =====================================================================

-- ---------- Helper checks ---------------------------------------------
-- "security definer" lets these look up memberships without being blocked
-- by the very rules they help enforce.

create function public.is_superadmin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.superadmins where user_id = auth.uid())
$$;

create function public.has_club_role(p_club_id uuid, p_roles public.club_role[])
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.club_members
    where club_id = p_club_id and user_id = auth.uid() and role = any (p_roles)
  )
$$;

create function public.is_club_member(p_club_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.club_members where club_id = p_club_id and user_id = auth.uid()
  )
$$;

create function public.is_coach(p_club_id uuid)
returns boolean language sql stable as $$
  select public.has_club_role(p_club_id, array['head_coach', 'assistant_coach']::public.club_role[])
$$;

create function public.is_head_coach(p_club_id uuid)
returns boolean language sql stable as $$
  select public.has_club_role(p_club_id, array['head_coach']::public.club_role[])
$$;

-- Head coach, or an assistant coach with the "create groups" switch on.
create function public.can_manage_groups(p_club_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.club_members
    where club_id = p_club_id and user_id = auth.uid()
      and (role = 'head_coach' or (role = 'assistant_coach' and can_create_groups))
  )
$$;

-- Head coach, or an assistant coach with the "move swimmers" switch on.
create function public.can_move_swimmers(p_club_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.club_members
    where club_id = p_club_id and user_id = auth.uid()
      and (role = 'head_coach' or (role = 'assistant_coach' and can_move_swimmers))
  )
$$;

-- Is the signed-in person this swimmer, or a linked parent of this swimmer?
create function public.is_self_or_parent_of(p_swimmer_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.swimmers where id = p_swimmer_id and user_id = auth.uid())
      or exists (select 1 from public.parent_links where swimmer_id = p_swimmer_id and parent_user_id = auth.uid())
$$;

-- Can the signed-in person see this swimmer's record at all?
--   coaches and swimmers of the same club: yes (teammates)
--   parents: only their linked children
create function public.can_see_swimmer(p_swimmer_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.swimmers s
    where s.id = p_swimmer_id
      and public.has_club_role(s.club_id, array['head_coach', 'assistant_coach', 'swimmer']::public.club_role[])
  ) or public.is_self_or_parent_of(p_swimmer_id)
$$;

-- ---------- Turn row-level security on everywhere ---------------------

alter table public.profiles      enable row level security;
alter table public.superadmins   enable row level security;
alter table public.clubs         enable row level security;
alter table public.club_members  enable row level security;
alter table public.groups        enable row level security;
alter table public.group_coaches enable row level security;
alter table public.swimmers      enable row level security;
alter table public.parent_links  enable row level security;
alter table public.invite_codes  enable row level security;
alter table public.group_moves   enable row level security;
alter table public.audit_log     enable row level security;

-- Logged-out visitors get nothing.
revoke all on all tables in schema public from anon;

-- ---------- profiles --------------------------------------------------

create policy "See own profile" on public.profiles
  for select to authenticated using (id = auth.uid());

-- Coaches see the profiles of everyone in their club; everyone in a club
-- sees their coaches' profiles.
create policy "See profiles of people in the same club" on public.profiles
  for select to authenticated using (
    exists (
      select 1 from public.club_members them
      where them.user_id = profiles.id
        and (public.is_coach(them.club_id)
             or (them.role in ('head_coach', 'assistant_coach') and public.is_club_member(them.club_id)))
    )
  );

create policy "Superadmin sees all profiles" on public.profiles
  for select to authenticated using (public.is_superadmin());

create policy "Edit own profile" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Only name and phone can be edited from the app.
revoke update on public.profiles from authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

-- ---------- superadmins -----------------------------------------------
-- No policies for writing: only the dashboard (service role) can add one.

create policy "See own superadmin row" on public.superadmins
  for select to authenticated using (user_id = auth.uid());

-- ---------- clubs -----------------------------------------------------

create policy "Members see their clubs" on public.clubs
  for select to authenticated using (public.is_club_member(id) or public.is_superadmin());

-- The head coach can edit the club's name, country and timezone.
-- Status and plan are changed only by the superadmin functions in part 3.
create policy "Head coach edits club details" on public.clubs
  for update to authenticated using (public.is_head_coach(id)) with check (public.is_head_coach(id));

revoke insert, update, delete on public.clubs from authenticated;
grant update (name, country, timezone) on public.clubs to authenticated;
-- New clubs are created with register_club() in part 3.

-- ---------- club_members ----------------------------------------------

create policy "See own memberships" on public.club_members
  for select to authenticated using (user_id = auth.uid());

create policy "Coaches see all members of their club" on public.club_members
  for select to authenticated using (public.is_coach(club_id));

create policy "Members see who the coaches are" on public.club_members
  for select to authenticated using (
    role in ('head_coach', 'assistant_coach') and public.is_club_member(club_id)
  );

create policy "Superadmin sees all members" on public.club_members
  for select to authenticated using (public.is_superadmin());

-- The head coach can remove assistant coaches, swimmers' logins and parents.
-- The head coach row itself can only change through transfer_head_coach().
create policy "Head coach removes members" on public.club_members
  for delete to authenticated using (public.is_head_coach(club_id) and role <> 'head_coach');

-- Anyone can leave a club, except the head coach (who must hand over first).
create policy "Leave a club" on public.club_members
  for delete to authenticated using (user_id = auth.uid() and role <> 'head_coach');

revoke insert, update on public.club_members from authenticated;
-- Joining happens through redeem_invite_code(); permission switches through
-- set_coach_permissions(), both in part 3.

-- ---------- groups ----------------------------------------------------

-- Group names are not sensitive: everyone in the club can see them.
create policy "Members see their club's groups" on public.groups
  for select to authenticated using (public.is_club_member(club_id) or public.is_superadmin());

create policy "Group managers create groups" on public.groups
  for insert to authenticated with check (public.can_manage_groups(club_id));

create policy "Group managers edit groups" on public.groups
  for update to authenticated
  using (public.can_manage_groups(club_id)) with check (public.can_manage_groups(club_id));

-- No delete policy: groups are archived (archived_at), never deleted.
revoke delete on public.groups from authenticated;
revoke update on public.groups from authenticated;
grant update (name, level, colour, description, archived_at) on public.groups to authenticated;

-- An archived group must be empty.
create function public.check_group_archive()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.archived_at is not null and old.archived_at is null then
    if exists (select 1 from public.swimmers where current_group_id = new.id and status = 'active') then
      raise exception 'Move every swimmer out of this group before archiving it.';
    end if;
    if exists (select 1 from public.group_moves where to_group_id = new.id and status = 'scheduled') then
      raise exception 'Cancel the scheduled moves into this group before archiving it.';
    end if;
  end if;
  return new;
end;
$$;

create trigger groups_check_archive
  before update of archived_at on public.groups
  for each row execute function public.check_group_archive();

-- ---------- group_coaches ---------------------------------------------

create policy "Members see group coaches" on public.group_coaches
  for select to authenticated using (public.is_club_member(club_id) or public.is_superadmin());

create policy "Group managers assign coaches" on public.group_coaches
  for insert to authenticated with check (public.can_manage_groups(club_id));

create policy "Group managers unassign coaches" on public.group_coaches
  for delete to authenticated using (public.can_manage_groups(club_id));

-- ---------- swimmers --------------------------------------------------

create policy "Coaches and teammates see swimmers" on public.swimmers
  for select to authenticated using (
    public.has_club_role(club_id, array['head_coach', 'assistant_coach', 'swimmer']::public.club_role[])
  );

create policy "Parents see their own children" on public.swimmers
  for select to authenticated using (public.is_self_or_parent_of(id));

create policy "Superadmin sees all swimmers" on public.swimmers
  for select to authenticated using (public.is_superadmin());

create policy "Coaches add swimmers" on public.swimmers
  for insert to authenticated with check (public.is_coach(club_id) and user_id is null);

create policy "Coaches edit swimmers" on public.swimmers
  for update to authenticated using (public.is_coach(club_id)) with check (public.is_coach(club_id));

-- The group can only change through move_swimmers(), and the login link
-- only through redeem_invite_code(). Swimmers are never hard-deleted:
-- they are marked as "left" so history and PBs are kept.
revoke update, delete on public.swimmers from authenticated;
grant update (first_name, last_name, birth_date, gender) on public.swimmers to authenticated;

-- When a swimmer is added with a first group, write a "joined" entry.
create function public.log_swimmer_joined()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.current_group_id is not null then
    insert into public.group_moves
      (club_id, swimmer_id, from_group_id, to_group_id, direction, effective_date, moved_by, notify)
    values
      (new.club_id, new.id, null, new.current_group_id, 'joined', new.joined_on, auth.uid(), false);
  end if;
  return new;
end;
$$;

create trigger swimmers_log_joined
  after insert on public.swimmers
  for each row execute function public.log_swimmer_joined();

-- A new swimmer cannot be placed into an archived group.
create function public.check_swimmer_group_active()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.current_group_id is not null and exists (
    select 1 from public.groups where id = new.current_group_id and archived_at is not null
  ) then
    raise exception 'That group is archived.';
  end if;
  return new;
end;
$$;

create trigger swimmers_check_group_active
  before insert on public.swimmers
  for each row execute function public.check_swimmer_group_active();

-- ---------- parent_links ----------------------------------------------

create policy "Parents see own links" on public.parent_links
  for select to authenticated using (parent_user_id = auth.uid());

create policy "Swimmers see their own parents" on public.parent_links
  for select to authenticated using (public.is_self_or_parent_of(swimmer_id));

create policy "Coaches see links in their club" on public.parent_links
  for select to authenticated using (public.is_coach(club_id) or public.is_superadmin());

create policy "Coaches remove links" on public.parent_links
  for delete to authenticated using (public.is_coach(club_id));

create policy "Parents remove own link" on public.parent_links
  for delete to authenticated using (parent_user_id = auth.uid());

revoke insert, update on public.parent_links from authenticated;
-- Links are created only by redeem_invite_code() in part 3.

-- ---------- invite_codes ----------------------------------------------

create policy "Coaches see their club's codes" on public.invite_codes
  for select to authenticated using (public.is_coach(club_id));

create policy "Coaches cancel codes" on public.invite_codes
  for delete to authenticated using (public.is_coach(club_id) and used_at is null);

revoke insert, update on public.invite_codes from authenticated;
-- Codes are made by create_invite_code() and used by redeem_invite_code().

-- ---------- group_moves -----------------------------------------------
-- Families read history through the family_group_history view below, which
-- hides the coach's reason unless "share reason" was ticked.

create policy "Coaches see move history" on public.group_moves
  for select to authenticated using (public.is_coach(club_id) or public.is_superadmin());

revoke insert, update, delete on public.group_moves from authenticated;
-- Moves are written only by move_swimmers() in part 3.

create view public.family_group_history
with (security_barrier = true) as
select
  m.id,
  m.club_id,
  m.swimmer_id,
  m.from_group_id,
  fg.name as from_group_name,
  m.to_group_id,
  tg.name as to_group_name,
  m.direction,
  m.effective_date,
  case when m.share_reason then m.reason end as reason,
  m.status,
  m.recorded_at
from public.group_moves m
left join public.groups fg on fg.id = m.from_group_id
left join public.groups tg on tg.id = m.to_group_id
where m.status <> 'cancelled'
  and public.is_self_or_parent_of(m.swimmer_id);

revoke all on public.family_group_history from anon;
grant select on public.family_group_history to authenticated;

-- ---------- audit_log -------------------------------------------------

create policy "Head coach reads the club's log" on public.audit_log
  for select to authenticated using (public.is_head_coach(club_id) or public.is_superadmin());

revoke insert, update, delete on public.audit_log from authenticated;
