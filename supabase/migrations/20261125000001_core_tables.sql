-- =====================================================================
-- SwimBase foundation, part 1 of 3: the core tables
-- =====================================================================
-- Plain-English summary:
--   * A "club" is one swim team. Every club's data is kept apart.
--   * A "profile" is one person who can log in (swimmer, parent or coach).
--   * A "club member" row says which role a person has in which club.
--   * "Groups" are training groups inside a club (Bronze, Silver, Gold...).
--   * A "swimmer" is the swimmer's record kept by the coach. It may or may
--     not have a login attached yet.
--   * "Parent links" say which parent can see which swimmer.
--   * "Invite codes" are the one-time codes used to join a club.
--   * "Group moves" is the permanent history of every group change.
--   * "Audit log" records sensitive actions (approvals, head coach changes,
--     permission changes) so clubs can trust how their data is handled.
--
-- Attendance, events, sessions and personal bests come in later phases.
-- =====================================================================

-- ---------- Fixed lists of allowed values ----------------------------

create type public.club_status as enum ('pending', 'approved', 'suspended');
create type public.club_plan as enum ('free', 'paid');
create type public.club_role as enum ('head_coach', 'assistant_coach', 'swimmer', 'parent');
create type public.swimmer_gender as enum ('male', 'female');
create type public.swimmer_status as enum ('active', 'left');
create type public.move_direction as enum ('joined', 'up', 'down', 'sideways', 'left_club');
create type public.move_status as enum ('scheduled', 'done', 'cancelled');
create type public.invite_role as enum ('assistant_coach', 'swimmer', 'parent');

-- ---------- People ----------------------------------------------------

-- One row per login. Created automatically when someone signs up.
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null default '',
  email       text,
  phone       text,
  created_at  timestamptz not null default now()
);

-- The platform owner(s). Rows are added by hand in the Supabase dashboard,
-- never from the app.
create table public.superadmins (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now()
);

-- ---------- Clubs -----------------------------------------------------

create table public.clubs (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (length(trim(name)) > 0),
  country      text not null default 'PH',
  timezone     text not null default 'Asia/Manila',
  status       public.club_status not null default 'pending',
  -- Free for now. The plan field is here so paid plans can be added later
  -- without reshaping the data.
  plan         public.club_plan not null default 'free',
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  approved_at  timestamptz,
  approved_by  uuid references auth.users (id) on delete set null
);

-- Which person has which role in which club.
create table public.club_members (
  id                 uuid primary key default gen_random_uuid(),
  club_id            uuid not null references public.clubs (id) on delete cascade,
  user_id            uuid not null references auth.users (id) on delete cascade,
  role               public.club_role not null,
  -- The two switches a head coach can turn on for an assistant coach.
  can_create_groups  boolean not null default false,
  can_move_swimmers  boolean not null default false,
  created_at         timestamptz not null default now(),
  unique (club_id, user_id, role),
  -- Switches only make sense for assistant coaches.
  check (role = 'assistant_coach' or (can_create_groups = false and can_move_swimmers = false))
);

-- Exactly one head coach per club (at most one here; the club is created
-- together with its head coach, so there is always one).
create unique index club_members_one_head_coach
  on public.club_members (club_id) where role = 'head_coach';
-- A person is either a coach (head or assistant) in a club, not both.
create unique index club_members_one_coach_row
  on public.club_members (club_id, user_id) where role in ('head_coach', 'assistant_coach');
create index club_members_user_idx on public.club_members (user_id);

-- ---------- Groups ----------------------------------------------------

create table public.groups (
  id           uuid primary key default gen_random_uuid(),
  club_id      uuid not null references public.clubs (id) on delete cascade,
  name         text not null check (length(trim(name)) > 0),
  -- 1 = entry level. Higher number = higher group. Two groups may share a level.
  level        integer not null default 1 check (level >= 1),
  colour       text,
  description  text,
  archived_at  timestamptz,
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  -- Lets other tables check that a group belongs to the same club.
  unique (id, club_id)
);
create index groups_club_idx on public.groups (club_id);

-- Coaches assigned to a group (used later for schedules).
create table public.group_coaches (
  group_id    uuid not null,
  club_id     uuid not null,
  user_id     uuid not null references auth.users (id) on delete cascade,
  primary key (group_id, user_id),
  foreign key (group_id, club_id) references public.groups (id, club_id) on delete cascade
);

-- ---------- Swimmers --------------------------------------------------

create table public.swimmers (
  id                uuid primary key default gen_random_uuid(),
  club_id           uuid not null references public.clubs (id) on delete cascade,
  -- Filled in when the swimmer redeems their invite code and gets a login.
  user_id           uuid references auth.users (id) on delete set null,
  first_name        text not null check (length(trim(first_name)) > 0),
  last_name         text not null check (length(trim(last_name)) > 0),
  birth_date        date not null,
  gender            public.swimmer_gender not null,
  current_group_id  uuid,
  status            public.swimmer_status not null default 'active',
  joined_on         date not null default current_date,
  left_on           date,
  created_at        timestamptz not null default now(),
  unique (id, club_id),
  -- The current group must be in the same club.
  foreign key (current_group_id, club_id) references public.groups (id, club_id)
);
create index swimmers_club_idx on public.swimmers (club_id);
create index swimmers_user_idx on public.swimmers (user_id);
-- One login is one swimmer per club.
create unique index swimmers_one_login_per_club
  on public.swimmers (club_id, user_id) where user_id is not null;

-- Current age, worked out from the birth date (birthdays are always shown).
create function public.age_on(birth date, on_date date default current_date)
returns integer language sql immutable as $$
  select extract(year from age(on_date, birth))::integer
$$;

-- ---------- Parent links ----------------------------------------------

create table public.parent_links (
  id              uuid primary key default gen_random_uuid(),
  club_id         uuid not null,
  swimmer_id      uuid not null,
  parent_user_id  uuid not null references auth.users (id) on delete cascade,
  created_at      timestamptz not null default now(),
  unique (swimmer_id, parent_user_id),
  foreign key (swimmer_id, club_id) references public.swimmers (id, club_id) on delete cascade
);
create index parent_links_parent_idx on public.parent_links (parent_user_id);

-- ---------- Invite codes ----------------------------------------------

create table public.invite_codes (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references public.clubs (id) on delete cascade,
  role        public.invite_role not null,
  -- Needed for swimmer and parent codes: which swimmer this code is for.
  swimmer_id  uuid,
  code        text not null unique,
  expires_at  timestamptz not null default (now() + interval '7 days'),
  used_at     timestamptz,
  used_by     uuid references auth.users (id) on delete set null,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  foreign key (swimmer_id, club_id) references public.swimmers (id, club_id) on delete cascade,
  check ((role = 'assistant_coach') = (swimmer_id is null))
);

-- ---------- Group move history ----------------------------------------

-- Append-only: rows are never edited or deleted, except that a scheduled
-- move can be marked cancelled.
create table public.group_moves (
  id              uuid primary key default gen_random_uuid(),
  club_id         uuid not null,
  swimmer_id      uuid not null,
  from_group_id   uuid,
  to_group_id     uuid,
  direction       public.move_direction not null,
  effective_date  date not null default current_date,
  reason          text,
  share_reason    boolean not null default false,
  notify          boolean not null default true,
  status          public.move_status not null default 'done',
  batch_id        uuid,
  moved_by        uuid references auth.users (id) on delete set null,
  recorded_at     timestamptz not null default now(),
  foreign key (swimmer_id, club_id) references public.swimmers (id, club_id) on delete cascade,
  foreign key (from_group_id, club_id) references public.groups (id, club_id),
  foreign key (to_group_id, club_id) references public.groups (id, club_id)
);
create index group_moves_swimmer_idx on public.group_moves (swimmer_id, recorded_at);
create index group_moves_club_idx on public.group_moves (club_id, recorded_at);

-- ---------- Audit log -------------------------------------------------

create table public.audit_log (
  id          bigint generated always as identity primary key,
  club_id     uuid references public.clubs (id) on delete cascade,
  actor_id    uuid references auth.users (id) on delete set null,
  action      text not null,
  details     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index audit_log_club_idx on public.audit_log (club_id, created_at);

-- ---------- Create a profile automatically on sign-up -----------------

create function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', '')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
