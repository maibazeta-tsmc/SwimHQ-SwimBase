-- Checks that the privacy rules do what the specs say.
-- Run with supabase/tests/run_tests.sh (uses a throwaway local database).
\set ON_ERROR_STOP 1
\set QUIET 1
set client_min_messages = warning;

-- ---------- test helpers (run as the database owner) ----------
create schema tests;
create table tests.people (name text primary key, id uuid not null);
create table tests.vars (name text primary key, id uuid);

create function tests.add_person(p_name text) returns void language plpgsql as $$
declare v uuid;
begin
  insert into auth.users (email, raw_user_meta_data)
  values (p_name || '@example.com', jsonb_build_object('full_name', initcap(p_name)))
  returning id into v;
  insert into tests.people values (p_name, v);
end $$;

-- Switch to a person (or '' for logged out).
create function tests.who(p_name text) returns uuid language sql stable as $$
  select id from tests.people where name = p_name
$$;
create function tests.v(p_name text) returns uuid language sql stable as $$
  select id from tests.vars where name = p_name
$$;
create function tests.set_v(p_name text, p_id uuid) returns void language sql as $$
  insert into tests.vars values (p_name, p_id) on conflict (name) do update set id = excluded.id
$$;
create function tests.eq(label text, got bigint, want bigint) returns void language plpgsql as $$
begin
  if got is distinct from want then raise exception 'FAIL: % (got %, want %)', label, got, want; end if;
  raise notice 'ok: %', label;
end $$;
create function tests.fails(label text, stmt text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    raise notice 'ok: % (blocked: %)', label, sqlerrm;
    return;
  end;
  raise exception 'FAIL: % should have been blocked', label;
end $$;
grant usage on schema tests to authenticated, anon;
grant select, insert, update on all tables in schema tests to authenticated, anon;
grant execute on all functions in schema tests to authenticated, anon;

select tests.add_person(n) from unnest(array['miguel','hc1','asst1','swim1','swim2','par1','hc2','stranger']) n;
insert into public.superadmins (user_id) select tests.who('miguel');

set client_min_messages = notice;

-- ===== Profiles are created on sign-up =====
select tests.eq('profile created for each sign-up', (select count(*) from public.profiles), 8);

-- ===== Head coach registers a club; it starts pending =====
select set_config('request.jwt.claim.sub', tests.who('hc1')::text, false);
set role authenticated;
select tests.set_v('clubA', public.register_club('Manila Marlins'));
select tests.eq('new club is pending', (select count(*) from public.clubs where id = tests.v('clubA') and status = 'pending'), 1);
select tests.eq('new club is on the free plan', (select count(*) from public.clubs where plan = 'free'), 1);
insert into public.groups (club_id, name, level) values (tests.v('clubA'), 'Bronze', 1), (tests.v('clubA'), 'Silver', 2), (tests.v('clubA'), 'Gold', 3);
select tests.set_v('bronze', (select id from public.groups where name = 'Bronze'));
select tests.set_v('silver', (select id from public.groups where name = 'Silver'));
select tests.set_v('gold',   (select id from public.groups where name = 'Gold'));
select tests.eq('pending club can set up groups', (select count(*) from public.groups), 3);
insert into public.swimmers (club_id, first_name, last_name, birth_date, gender, current_group_id)
values (tests.v('clubA'), 'Ana', 'Reyes', '2013-05-02', 'female', tests.v('bronze')),
       (tests.v('clubA'), 'Ben', 'Cruz',  '2012-08-14', 'male',   tests.v('bronze'));
select tests.set_v('ana', (select id from public.swimmers where first_name = 'Ana'));
select tests.set_v('ben', (select id from public.swimmers where first_name = 'Ben'));
select tests.eq('adding a swimmer logs a "joined" entry', (select count(*) from public.group_moves where direction = 'joined'), 2);
select tests.fails('pending club cannot invite swimmers',
  format('select public.create_invite_code(%L, ''swimmer'', %L)', tests.v('clubA'), tests.v('ana')));
select tests.fails('head coach cannot approve own club', format('select public.approve_club(%L)', tests.v('clubA')));
select tests.fails('head coach cannot change status directly', format('update public.clubs set status = ''approved'' where id = %L', tests.v('clubA')));
select tests.fails('head coach cannot change plan directly', format('update public.clubs set plan = ''paid'' where id = %L', tests.v('clubA')));
create temp table codes (name text, code text);
grant all on codes to authenticated;
insert into codes values ('coach', public.create_invite_code(tests.v('clubA'), 'assistant_coach'));
reset role;

-- ===== Superadmin approves =====
select set_config('request.jwt.claim.sub', tests.who('miguel')::text, false);
set role authenticated;
select public.approve_club(tests.v('clubA'));
select tests.eq('superadmin sees the club', (select count(*) from public.clubs), 1);
reset role;

-- ===== Invites: coach, swimmer, parent =====
select set_config('request.jwt.claim.sub', tests.who('hc1')::text, false);
set role authenticated;
insert into codes values ('ana', public.create_invite_code(tests.v('clubA'), 'swimmer', tests.v('ana')));
insert into codes values ('ben', public.create_invite_code(tests.v('clubA'), 'swimmer', tests.v('ben')));
insert into codes values ('ana_parent', public.create_invite_code(tests.v('clubA'), 'parent', tests.v('ana')));
select tests.eq('code format is XXXX-XXXX', (select count(*) from codes where code ~ '^[A-Z2-9]{4}-[A-Z2-9]{4}$'), 4);
reset role;

select set_config('request.jwt.claim.sub', tests.who('asst1')::text, false);
set role authenticated;
select public.redeem_invite_code((select code from codes where name = 'coach'));
select tests.fails('a code works only once', format('select public.redeem_invite_code(%L)', (select code from codes where name = 'coach')));
reset role;

select set_config('request.jwt.claim.sub', tests.who('swim1')::text, false);
set role authenticated;
select public.redeem_invite_code(lower(replace((select code from codes where name = 'ana'), '-', '')));
reset role;
select set_config('request.jwt.claim.sub', tests.who('swim2')::text, false);
set role authenticated;
select public.redeem_invite_code((select code from codes where name = 'ben'));
reset role;
select set_config('request.jwt.claim.sub', tests.who('par1')::text, false);
set role authenticated;
select public.redeem_invite_code((select code from codes where name = 'ana_parent'));
reset role;

-- ===== Assistant coach permissions =====
select set_config('request.jwt.claim.sub', tests.who('asst1')::text, false);
set role authenticated;
select tests.eq('assistant sees all swimmers', (select count(*) from public.swimmers), 2);
select tests.fails('assistant without switch cannot create groups',
  format('insert into public.groups (club_id, name) values (%L, ''Masters'')', tests.v('clubA')));
select tests.fails('assistant without switch cannot move swimmers',
  format('select public.move_swimmers(array[%L]::uuid[], %L)', tests.v('ana'), tests.v('silver')));
select tests.fails('assistant cannot give themselves permissions',
  format('select public.set_coach_permissions(%L, true, true)', (select id from public.club_members where user_id = tests.who('asst1'))));
reset role;

select set_config('request.jwt.claim.sub', tests.who('hc1')::text, false);
set role authenticated;
select public.set_coach_permissions((select id from public.club_members where user_id = tests.who('asst1')), false, true);
select tests.eq('permission change is logged', (select count(*) from public.audit_log where action = 'coach_permissions_changed'), 1);
reset role;

select set_config('request.jwt.claim.sub', tests.who('asst1')::text, false);
set role authenticated;
select public.move_swimmers(array[tests.v('ana')], tests.v('silver'), null, 'Great sets this month', false);
select tests.eq('move is recorded as "up"', (select count(*) from public.group_moves where swimmer_id = tests.v('ana') and direction = 'up' and status = 'done'), 1);
select tests.eq('swimmer is now in Silver', (select count(*) from public.swimmers where id = tests.v('ana') and current_group_id = tests.v('silver')), 1);
select tests.fails('stale move is rejected (two coaches at once)',
  format('select public.move_swimmers(array[%L]::uuid[], %L, null, null, false, true, array[%L]::uuid[])', tests.v('ana'), tests.v('gold'), tests.v('bronze')));
select public.move_swimmers(array[tests.v('ben')], tests.v('gold'), current_date + 10);
select tests.eq('future move is scheduled, not applied', (select count(*) from public.swimmers where id = tests.v('ben') and current_group_id = tests.v('bronze')), 1);
select tests.fails('assistant still cannot create groups (only move switch on)',
  format('insert into public.groups (club_id, name) values (%L, ''Masters'')', tests.v('clubA')));
reset role;

-- ===== Swimmers see teammates; parents only their children =====
select set_config('request.jwt.claim.sub', tests.who('swim1')::text, false);
set role authenticated;
select tests.eq('swimmer sees teammates', (select count(*) from public.swimmers), 2);
select tests.eq('swimmer sees their group history (own only)', (select count(*) from public.family_group_history), 2);
select tests.eq('swimmer cannot read the raw move table', (select count(*) from public.group_moves), 0);
select tests.eq('coach''s reason is hidden from family', (select count(*) from public.family_group_history where reason is not null), 0);
select tests.fails('swimmer cannot change their own group',
  format('update public.swimmers set current_group_id = %L where id = %L', tests.v('gold'), tests.v('ana')));
update public.swimmers set first_name = 'X' where id = tests.v('ben');
select tests.eq('swimmer cannot edit swimmer records (change is ignored)',
  (select count(*) from public.swimmers where first_name = 'X'), 0);
select tests.fails('swimmer cannot add groups',
  format('insert into public.groups (club_id, name) values (%L, ''X'')', tests.v('clubA')));
select tests.eq('swimmer sees coach profiles but not teammates'' profiles',
  (select count(*) from public.profiles), 3); -- self + hc1 + asst1
reset role;

select set_config('request.jwt.claim.sub', tests.who('par1')::text, false);
set role authenticated;
select tests.eq('parent sees only their own child', (select count(*) from public.swimmers), 1);
select tests.eq('parent sees their child''s history', (select count(*) from public.family_group_history), 2);
select tests.eq('parent cannot see invite codes', (select count(*) from public.invite_codes), 0);
select tests.eq('parent cannot see the audit log', (select count(*) from public.audit_log), 0);
reset role;

-- ===== Other clubs see nothing =====
select set_config('request.jwt.claim.sub', tests.who('hc2')::text, false);
set role authenticated;
select tests.set_v('clubB', public.register_club('Cebu Dolphins'));
insert into public.groups (club_id, name) values (tests.v('clubB'), 'Squad');
select tests.eq('other club sees only its own club', (select count(*) from public.clubs), 1);
select tests.eq('other club sees no swimmers from club A', (select count(*) from public.swimmers), 0);
select tests.eq('other club sees only its own groups', (select count(*) from public.groups), 1);
select tests.eq('other club sees no members of club A', (select count(*) from public.club_members where club_id = tests.v('clubA')), 0);
select tests.fails('other club cannot move club A swimmers',
  format('select public.move_swimmers(array[%L]::uuid[], %L)', tests.v('ana'), (select id from public.groups where name = 'Squad')));
select tests.fails('other club cannot add groups to club A',
  format('insert into public.groups (club_id, name) values (%L, ''Spy'')', tests.v('clubA')));
reset role;

select set_config('request.jwt.claim.sub', tests.who('stranger')::text, false);
set role authenticated;
select tests.eq('signed-in stranger sees no swimmers', (select count(*) from public.swimmers), 0);
select tests.eq('signed-in stranger sees no clubs', (select count(*) from public.clubs), 0);
reset role;

select set_config('request.jwt.claim.sub', '', false);
set role anon;
select tests.fails('logged-out visitor cannot read swimmers', 'select count(*) from public.swimmers');
select tests.fails('logged-out visitor cannot register a club', 'select public.register_club(''X'')');
reset role;

-- ===== Superadmin: read everything, change only approvals and head coach =====
select set_config('request.jwt.claim.sub', tests.who('miguel')::text, false);
set role authenticated;
select tests.eq('superadmin sees all clubs', (select count(*) from public.clubs), 2);
select tests.eq('superadmin sees all swimmers', (select count(*) from public.swimmers), 2);
select tests.fails('superadmin cannot add groups inside a club',
  format('insert into public.groups (club_id, name) values (%L, ''X'')', tests.v('clubA')));
select tests.fails('superadmin cannot move swimmers',
  format('select public.move_swimmers(array[%L]::uuid[], %L)', tests.v('ana'), tests.v('gold')));
update public.swimmers set first_name = 'X' where id = tests.v('ana');
select tests.eq('superadmin cannot edit swimmers (change is ignored)',
  (select count(*) from public.swimmers where first_name = 'X'), 0);
select public.transfer_head_coach(tests.v('clubA'), tests.who('asst1'));
select tests.eq('head coach reassigned by superadmin',
  (select count(*) from public.club_members where club_id = tests.v('clubA') and role = 'head_coach' and user_id = tests.who('asst1')), 1);
select tests.eq('old head coach stays as assistant',
  (select count(*) from public.club_members where club_id = tests.v('clubA') and role = 'assistant_coach' and user_id = tests.who('hc1')), 1);
select tests.eq('exactly one head coach', (select count(*) from public.club_members where club_id = tests.v('clubA') and role = 'head_coach'), 1);
reset role;

-- ===== Scheduled moves and leaving =====
update public.group_moves set effective_date = current_date where swimmer_id = tests.v('ben') and status = 'scheduled';
select tests.eq('daily job applies due moves', public.apply_scheduled_moves(), 1);
select tests.eq('Ben is now in Gold', (select count(*) from public.swimmers where id = tests.v('ben') and current_group_id = tests.v('gold')), 1);

select set_config('request.jwt.claim.sub', tests.who('asst1')::text, false);
set role authenticated;
select tests.fails('cannot archive a group that still has swimmers',
  format('update public.groups set archived_at = now() where id = %L', tests.v('gold')));
select public.mark_swimmer_left(tests.v('ana'));
select tests.eq('leaving keeps the swimmer record', (select count(*) from public.swimmers where id = tests.v('ana') and status = 'left'), 1);
select tests.eq('leaving ends parent links', (select count(*) from public.parent_links where swimmer_id = tests.v('ana')), 0);
update public.groups set archived_at = now() where id = tests.v('silver');
select tests.eq('empty group can be archived', (select count(*) from public.groups where archived_at is not null), 1);
select tests.fails('groups cannot be deleted', format('delete from public.groups where id = %L', tests.v('silver')));
-- What the coach screens do:
update public.groups set archived_at = null where id = tests.v('silver');
select tests.eq('archived group can be restored', (select count(*) from public.groups where archived_at is not null), 0);
insert into public.swimmers (club_id, first_name, last_name, birth_date, gender)
values (tests.v('clubA'), 'Cara', 'Diaz', '2015-02-03', 'female');
select tests.eq('swimmer can be added with no group (Unassigned)',
  (select count(*) from public.swimmers where first_name = 'Cara' and current_group_id is null), 1);
select public.move_swimmers(array[(select id from public.swimmers where first_name = 'Cara')], tests.v('silver'),
  p_expected_from_group_ids => array[null]::uuid[]);
select tests.eq('unassigned swimmer put in a group counts as joined',
  (select count(*) from public.group_moves gm join public.swimmers s on s.id = gm.swimmer_id
   where s.first_name = 'Cara' and gm.direction = 'joined'), 1);
reset role;

-- ===== Superadmin approves a pending club from the app =====
select set_config('request.jwt.claim.sub', tests.who('miguel')::text, false);
set role authenticated;
select tests.eq('superadmin sees the pending club', (select count(*) from public.clubs where status = 'pending'), 1);
select public.approve_club(tests.v('clubB'));
select tests.eq('club approved', (select count(*) from public.clubs where id = tests.v('clubB') and status = 'approved'), 1);
reset role;

\echo 'All privacy rule tests passed.'
