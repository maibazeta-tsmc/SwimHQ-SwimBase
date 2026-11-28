-- Checks the swim times and personal bests rules (runs after
-- events_test.sql and reuses its people, clubs and helpers).
-- In club A: asst1 is head coach, hc1 is an assistant with no switches,
-- Ben (login swim2) and Dan (login swim3, parent par2) and Eva (no login)
-- are swimmers. hc2 runs club B.
\set ON_ERROR_STOP 1
\set QUIET 1
set client_min_messages = notice;

-- ===== An assistant adds times =====
select set_config('request.jwt.claim.sub', tests.who('hc1')::text, false);
set role authenticated;
select tests.set_v('r_dan1', public.save_swim_result(
  null, tests.v('dan'), 'scm', 'free', 100, 6610, 'Club time trial', tests.today() - 20));
select tests.set_v('r_dan2', public.save_swim_result(
  null, tests.v('dan'), 'scm', 'free', 100, 6542, ' Regional Champs ', tests.today() - 5));
select public.save_swim_result(null, tests.v('dan'), 'scm', 'free', 100, 6700, 'League meet', tests.today() - 2);
select public.save_swim_result(null, tests.v('dan'), 'lcm', 'back', 50, 3520, 'Summer Open', tests.today() - 40);
select public.save_swim_result(null, tests.v('eva'), 'scm', 'free', 100, 6400, 'Regional Champs', tests.today() - 5);
select public.save_swim_result(null, tests.v('ben'), 'scm', 'im', 100, 7500, 'Regional Champs', tests.today() - 5);
select tests.eq('assistant adds times', (select count(*) from public.swim_results), 6);
select tests.ok('meet name is trimmed',
  (select meet_name from public.swim_results where id = tests.v('r_dan2')) = 'Regional Champs');
select tests.eq('PB is the fastest swim',
  (select min(time_cs) from public.swim_results
    where swimmer_id = tests.v('dan') and course = 'scm' and stroke = 'free' and distance = 100), 6542);
select tests.fails('the app can''t read the notification list', 'select count(*) from public.result_notifications');
select tests.fails('100 IM is SCM only',
  format('select public.save_swim_result(null, %L, ''lcm'', ''im'', 100, 7000, ''X'', %L)', tests.v('dan'), tests.today()));
select tests.fails('no 800 Back',
  format('select public.save_swim_result(null, %L, ''scm'', ''back'', 800, 70000, ''X'', %L)', tests.v('dan'), tests.today()));
select tests.fails('time is needed',
  format('select public.save_swim_result(null, %L, ''scm'', ''free'', 50, 0, ''X'', %L)', tests.v('dan'), tests.today()));
select tests.fails('meet name is needed',
  format('select public.save_swim_result(null, %L, ''scm'', ''free'', 50, 3000, '' '', %L)', tests.v('dan'), tests.today()));
select tests.fails('date can''t be in the future',
  format('select public.save_swim_result(null, %L, ''scm'', ''free'', 50, 3000, ''X'', %L)', tests.v('dan'), tests.today() + 1));
select tests.fails('date can''t be before birth',
  format('select public.save_swim_result(null, %L, ''scm'', ''free'', 50, 3000, ''X'', ''2000-01-01'')', tests.v('dan')));
select tests.fails('meet must be from this club',
  format('select public.save_swim_result(null, %L, ''scm'', ''free'', 50, 3000, ''X'', %L, %L)',
         tests.v('dan'), tests.today(), gen_random_uuid()));
select tests.fails('cannot write times directly',
  format('insert into public.swim_results (club_id, swimmer_id, course, stroke, distance, time_cs, meet_name, swim_date)
          values (%L, %L, ''scm'', ''free'', 50, 3000, ''X'', current_date)', tests.v('clubA'), tests.v('dan')));
select tests.fails('cannot change times directly',
  format('update public.swim_results set time_cs = 1 where id = %L', tests.v('r_dan1')));

-- Fixing a typo keeps the old value in the history.
select public.save_swim_result(tests.v('r_dan1'), tests.v('dan'), 'scm', 'free', 100, 6601, 'Club time trial', tests.today() - 20);
select tests.eq('edit changes the time and records who',
  (select count(*) from public.swim_results where id = tests.v('r_dan1') and time_cs = 6601
     and edited_by = tests.who('hc1') and edited_at is not null), 1);
select tests.eq('history keeps the old time',
  (select count(*) from public.swim_result_changes where result_id = tests.v('r_dan1') and action = 'edited'
     and (old_values ->> 'time_cs')::int = 6610 and changed_by = tests.who('hc1')), 1);
reset role;

select tests.eq('each new time waits to notify the family', (select count(*) from public.result_notifications), 6);
select tests.eq('first swims and faster swims count as new PBs',
  (select count(*) from public.result_notifications where is_pb), 5);
select tests.eq('a slower swim is not a PB',
  (select count(*) from public.result_notifications where not is_pb and meet_name = 'League meet'), 1);
select tests.eq('editing sends nothing new', (select count(*) from public.result_notifications), 6);

-- ===== Families =====
select set_config('request.jwt.claim.sub', tests.who('swim3')::text, false);
set role authenticated;
select tests.eq('swimmer sees own and teammates'' times', (select count(*) from public.swim_results), 6);
select tests.fails('swimmer can''t add times',
  format('select public.save_swim_result(null, %L, ''scm'', ''free'', 50, 3000, ''X'', %L)', tests.v('dan'), tests.today()));
select tests.fails('swimmer can''t delete times', format('select public.delete_swim_result(%L)', tests.v('r_dan1')));
select tests.eq('swimmer can''t see the change history', (select count(*) from public.swim_result_changes), 0);
reset role;

select set_config('request.jwt.claim.sub', tests.who('par2')::text, false);
set role authenticated;
select tests.eq('parent sees only their child''s times', (select count(*) from public.swim_results), 4);
select tests.eq('...and none of the teammates''',
  (select count(*) from public.swim_results where swimmer_id <> tests.v('dan')), 0);
select tests.fails('parent can''t add times',
  format('select public.save_swim_result(null, %L, ''scm'', ''free'', 50, 3000, ''X'', %L)', tests.v('dan'), tests.today()));
reset role;

-- ===== Head coach deletes a time =====
select set_config('request.jwt.claim.sub', tests.who('asst1')::text, false);
set role authenticated;
select public.delete_swim_result(tests.v('r_dan2'));
select tests.eq('deleted time is gone', (select count(*) from public.swim_results where id = tests.v('r_dan2')), 0);
select tests.eq('PB falls back to the next fastest',
  (select min(time_cs) from public.swim_results
    where swimmer_id = tests.v('dan') and course = 'scm' and stroke = 'free' and distance = 100), 6601);
select tests.eq('history keeps the deleted time',
  (select count(*) from public.swim_result_changes where result_id = tests.v('r_dan2') and action = 'deleted'), 1);
reset role;

-- ===== Other clubs and the superadmin =====
select set_config('request.jwt.claim.sub', tests.who('hc2')::text, false);
set role authenticated;
select tests.eq('other club sees no times', (select count(*) from public.swim_results), 0);
select tests.fails('other club can''t add times to club A',
  format('select public.save_swim_result(null, %L, ''scm'', ''free'', 50, 3000, ''X'', %L)', tests.v('dan'), tests.today()));
select tests.fails('other club can''t delete club A''s times', format('select public.delete_swim_result(%L)', tests.v('r_dan1')));
reset role;

select set_config('request.jwt.claim.sub', tests.who('miguel')::text, false);
set role authenticated;
select tests.eq('superadmin can read times', (select count(*) from public.swim_results), 5);
select tests.fails('superadmin can''t add times',
  format('select public.save_swim_result(null, %L, ''scm'', ''free'', 50, 3000, ''X'', %L)', tests.v('dan'), tests.today()));
reset role;

\echo 'All personal bests tests passed.'
