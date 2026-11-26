-- Checks the training schedule rules (runs after privacy_rules_test.sql and
-- reuses its people, clubs and helpers).
-- At this point in club A: asst1 is head coach, hc1 is an assistant with no
-- switches, Ben (login swim2) is in Gold, Cara is in Silver, Bronze is empty.
\set ON_ERROR_STOP 1
\set QUIET 1
set client_min_messages = notice;

create function tests.today() returns date language sql stable as $$
  select public.club_today(tests.v('clubA'))
$$;
create function tests.ok(label text, cond boolean) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FAIL: %', label; end if;
  raise notice 'ok: %', label;
end $$;
grant execute on function tests.today(), tests.ok(text, boolean) to authenticated, anon;

-- ===== Head coach sets up Gold's weekly pattern =====
select set_config('request.jwt.claim.sub', tests.who('asst1')::text, false);
set role authenticated;
select tests.set_v('gold_pm_mon', public.add_weekly_session(tests.v('gold'), 1, '16:30', '19:00', null, 'Main pool'));
select public.add_weekly_session(tests.v('gold'), d, '16:30', '19:00') from generate_series(2, 5) d;
select tests.set_v('gold_am_tue', public.add_weekly_session(tests.v('gold'), 2, '06:00', '07:00', 'AM'));
select tests.eq('weekly pattern has 6 lines', (select count(*) from public.weekly_sessions where group_id = tests.v('gold')), 6);
select tests.eq('sessions are created 90 days ahead (Mon-Fri PM + Tue AM)',
  (select count(*) from public.sessions where group_id = tests.v('gold')),
  (select count(*) from generate_series(tests.today(), tests.today() + 90, interval '1 day') d
    where extract(isodow from d) between 1 and 5)
  + (select count(*) from generate_series(tests.today(), tests.today() + 90, interval '1 day') d
    where extract(isodow from d) = 2));
select tests.eq('no sessions on weekends',
  (select count(*) from public.sessions where group_id = tests.v('gold') and extract(isodow from session_date) in (6, 7)), 0);
select tests.fails('end time must be after start time',
  format('select public.add_weekly_session(%L, 3, ''10:00'', ''09:00'')', tests.v('gold')));
select tests.fails('cannot write sessions directly',
  format('insert into public.sessions (club_id, group_id, session_date, start_time, end_time) values (%L, %L, current_date, ''10:00'', ''11:00'')',
         tests.v('clubA'), tests.v('gold')));
select tests.fails('the nightly top-up is not callable from the app', 'select public.top_up_all_sessions()');
reset role;
select tests.eq('nightly top-up adds nothing when already full', public.top_up_all_sessions(), 0);

-- ===== Who can edit which group's schedule =====
select set_config('request.jwt.claim.sub', tests.who('hc1')::text, false);
set role authenticated;
select tests.fails('assistant not assigned to Gold cannot change its schedule',
  format('select public.add_weekly_session(%L, 6, ''07:00'', ''09:00'')', tests.v('gold')));
reset role;
select set_config('request.jwt.claim.sub', tests.who('asst1')::text, false);
set role authenticated;
insert into public.group_coaches (group_id, club_id, user_id) values (tests.v('bronze'), tests.v('clubA'), tests.who('hc1'));
reset role;
select set_config('request.jwt.claim.sub', tests.who('hc1')::text, false);
set role authenticated;
select tests.eq('assigned assistant can edit Bronze', public.can_edit_schedule(tests.v('bronze'))::int, 1);
select tests.eq('...but not Gold', public.can_edit_schedule(tests.v('gold'))::int, 0);
select public.add_weekly_session(tests.v('bronze'), 6, '07:00', '09:00');
select tests.fails('assistant cannot set a whole-club rest day',
  format('select public.add_rest_days(%L, null, %L, %L)', tests.v('clubA'), tests.today(), tests.today()));
reset role;

-- ===== Families and other clubs =====
select set_config('request.jwt.claim.sub', tests.who('swim2')::text, false);
set role authenticated;
select tests.ok('swimmer sees the club''s sessions',
  (select count(*) from public.sessions where group_id = tests.v('gold')) > 0);
select tests.fails('swimmer cannot add sessions',
  format('select public.add_one_off_session(array[%L]::uuid[], %L, ''07:00'', ''09:00'')', tests.v('gold'), tests.today()));
select tests.fails('swimmer cannot cancel sessions',
  format('select public.cancel_sessions(array[(select id from public.sessions limit 1)])'));
reset role;
select set_config('request.jwt.claim.sub', tests.who('hc2')::text, false);
set role authenticated;
select tests.eq('other club sees none of club A''s sessions', (select count(*) from public.sessions), 0);
select tests.eq('other club sees none of club A''s weekly pattern', (select count(*) from public.weekly_sessions), 0);
select tests.fails('other club cannot read club A swimmer''s schedule',
  format('select * from public.swimmer_schedule(%L, %L, %L)', tests.v('ben'), tests.today(), tests.today() + 7));
reset role;

-- ===== One day at a time =====
select set_config('request.jwt.claim.sub', tests.who('asst1')::text, false);
set role authenticated;
select tests.set_v('next_gold',
  (select id from public.sessions where group_id = tests.v('gold') and session_date > tests.today()
   order by session_date, start_time limit 1));
select tests.eq('cancel one session', public.cancel_sessions(array[tests.v('next_gold')], 'Pool maintenance'), 1);
select tests.eq('cancelled session keeps its reason and time',
  (select count(*) from public.sessions where id = tests.v('next_gold') and status = 'cancelled'
     and cancel_reason = 'Pool maintenance' and cancelled_at is not null), 1);
select public.restore_session(tests.v('next_gold'));
select tests.eq('restore it', (select count(*) from public.sessions where id = tests.v('next_gold') and status = 'scheduled'), 1);
select public.change_session_time(tests.v('next_gold'), '17:00', '19:30');
select tests.eq('change one day''s time',
  (select count(*) from public.sessions where id = tests.v('next_gold') and start_time = '17:00'), 1);
select tests.eq('one-off session for two groups at once',
  public.add_one_off_session(array[tests.v('gold'), tests.v('silver')], tests.today() + 3, '07:00', '09:00', 'Time trial'), 2);
select tests.fails('cannot add a one-off in the past',
  format('select public.add_one_off_session(array[%L]::uuid[], %L, ''07:00'', ''09:00'')', tests.v('gold'), tests.today() - 1));

-- ===== Rest days =====
select tests.set_v('gold_break', null);
select tests.ok('rest days cancel the sessions inside them',
  public.add_rest_days(tests.v('clubA'), array[tests.v('gold')], tests.today() + 1, tests.today() + 7, 'break', 'Sembreak') > 0);
select tests.set_v('gold_break', (select id from public.rest_days where title = 'Sembreak'));
select tests.eq('no scheduled Gold sessions left in the break',
  (select count(*) from public.sessions where group_id = tests.v('gold') and status = 'scheduled'
     and session_date between tests.today() + 1 and tests.today() + 7), 0);
select tests.eq('other groups keep training',
  (select count(*) from public.sessions where group_id = tests.v('silver') and status = 'cancelled'), 0);
select tests.fails('a rest-day session is restored by removing the rest day',
  format('select public.restore_session((select id from public.sessions where rest_day_id = %L limit 1))', tests.v('gold_break')));
-- A whole-club rest day overlapping the break, then remove the break:
select public.add_rest_days(tests.v('clubA'), null, tests.today() + 7, tests.today() + 7, 'rest_day', 'Holiday');
select public.remove_rest_day(tests.v('gold_break'));
select tests.eq('removing the break brings its sessions back',
  (select count(*) from public.sessions where group_id = tests.v('gold') and status = 'cancelled'
     and session_date between tests.today() + 1 and tests.today() + 6), 0);
select tests.eq('...except the day still covered by the club holiday',
  (select count(*) from public.sessions where group_id = tests.v('gold') and status = 'scheduled'
     and session_date = tests.today() + 7), 0);
select public.remove_rest_day((select id from public.rest_days where title = 'Holiday'));
select tests.eq('all rest days gone', (select count(*) from public.rest_days), 0);

-- ===== Changing the weekly pattern =====
select public.end_weekly_session(tests.v('gold_am_tue'), tests.today() + 13);
select tests.eq('ending a weekly line removes its later sessions',
  (select count(*) from public.sessions where weekly_session_id = tests.v('gold_am_tue') and session_date > tests.today() + 13), 0);
select tests.ok('...and keeps the earlier ones',
  (select count(*) from public.sessions where weekly_session_id = tests.v('gold_am_tue')) > 0);
select tests.fails('cannot end a line in the past',
  format('select public.end_weekly_session(%L, %L)', tests.v('gold_pm_mon'), tests.today() - 5));
select tests.eq('copy Gold''s pattern to Silver', public.copy_weekly_schedule(tests.v('gold'), tests.v('silver')), 6);

-- ===== A moved swimmer follows the new group from the move date =====
select tests.ok('coach can read a swimmer''s schedule',
  (select count(*) from public.swimmer_schedule(tests.v('ben'), tests.today(), tests.today() + 27)) > 0);
select public.move_swimmers(array[tests.v('ben')], tests.v('bronze'), tests.today() + 14);
reset role;

select set_config('request.jwt.claim.sub', tests.who('swim2')::text, false);
set role authenticated;
select tests.eq('before the move date Ben sees only Gold',
  (select count(*) from public.swimmer_schedule(tests.v('ben'), tests.today(), tests.today() + 27)
    where session_date < tests.today() + 14 and group_id <> tests.v('gold')), 0);
select tests.eq('from the move date Ben sees only Bronze',
  (select count(*) from public.swimmer_schedule(tests.v('ben'), tests.today(), tests.today() + 27)
    where session_date >= tests.today() + 14 and group_id <> tests.v('bronze')), 0);
select tests.eq('Ben sees Bronze''s Saturday sessions after the move',
  (select count(*) from public.swimmer_schedule(tests.v('ben'), tests.today() + 14, tests.today() + 27)
    where extract(isodow from session_date) = 6), 2);
select tests.fails('range is limited to 120 days',
  format('select * from public.swimmer_schedule(%L, %L, %L)', tests.v('ben'), tests.today(), tests.today() + 200));
reset role;

-- ===== Archiving a group clears its future sessions =====
select set_config('request.jwt.claim.sub', tests.who('asst1')::text, false);
set role authenticated;
select public.cancel_scheduled_move((select id from public.group_moves where swimmer_id = tests.v('ben') and status = 'scheduled'));
update public.groups set archived_at = now() where id = tests.v('bronze');
select tests.eq('archived group has no future sessions',
  (select count(*) from public.sessions where group_id = tests.v('bronze') and session_date >= tests.today()), 0);
update public.groups set archived_at = null where id = tests.v('bronze');
select tests.ok('restoring the group brings its sessions back',
  (select count(*) from public.sessions where group_id = tests.v('bronze')) > 0);
reset role;

\echo 'All schedule tests passed.'
