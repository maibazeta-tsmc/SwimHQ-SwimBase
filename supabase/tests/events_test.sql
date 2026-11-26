-- Checks the events rules (runs after attendance_test.sql and reuses its
-- people, clubs and helpers).
-- At this point in club A: asst1 is head coach, hc1 is an assistant with no
-- switches (assigned to Bronze), Ben (login swim2) is in Gold, Dan (login
-- swim3, parent par2) is in Silver, Eva has moved to Gold.
\set ON_ERROR_STOP 1
\set QUIET 1
set client_min_messages = notice;

-- ===== An assistant adds events =====
select set_config('request.jwt.claim.sub', tests.who('hc1')::text, false);
set role authenticated;
select tests.set_v('ev_club', public.save_event(
  null, tests.v('clubA'), 'Club Christmas party', 'social', tests.today() + 20, tests.today() + 20,
  '18:00', '21:00', 'Clubhouse', p_notes => 'Bring a gift'));
select tests.set_v('ev_silver', public.save_event(
  null, tests.v('clubA'), 'Silver time trial', 'meet', tests.today() + 5, tests.today() + 5,
  p_venue => 'Main pool', p_course => 'scm', p_link => 'example.com/meet',
  p_group_ids => array[tests.v('silver')]));
select tests.eq('assistant adds events', (select count(*) from public.events where club_id = tests.v('clubA')), 2);
select tests.eq('group event is for Silver only',
  (select count(*) from public.event_groups where event_id = tests.v('ev_silver') and group_id = tests.v('silver')), 1);
select tests.ok('a link without https:// gets it',
  (select link from public.events where id = tests.v('ev_silver')) = 'https://example.com/meet');
select tests.fails('the app can''t read the notification list', 'select count(*) from public.event_notifications');
select tests.fails('title is needed',
  format('select public.save_event(null, %L, '' '', ''meet'', %L, %L)', tests.v('clubA'), tests.today(), tests.today()));
select tests.fails('last day must be on or after the first',
  format('select public.save_event(null, %L, ''X'', ''meet'', %L, %L)', tests.v('clubA'), tests.today() + 2, tests.today()));
select tests.fails('end time must be after start time on a one-day event',
  format('select public.save_event(null, %L, ''X'', ''meet'', %L, %L, ''10:00'', ''09:00'')', tests.v('clubA'), tests.today(), tests.today()));
select tests.fails('groups must be from this club',
  format('select public.save_event(null, %L, ''X'', ''meet'', %L, %L, p_group_ids => array[%L]::uuid[])',
         tests.v('clubA'), tests.today(), tests.today(), tests.v('clubB')));
select tests.fails('cannot write events directly',
  format('insert into public.events (club_id, title, start_date, end_date) values (%L, ''X'', current_date, current_date)', tests.v('clubA')));
select tests.fails('assistant without schedule rights can''t cancel Gold training with an event',
  format('select public.save_event(null, %L, ''X'', ''meet'', %L, %L, p_group_ids => array[%L]::uuid[], p_cancel_training => true)',
         tests.v('clubA'), tests.today() + 1, tests.today() + 1, tests.v('gold')));
-- Editing marks the event as updated.
select public.save_event(tests.v('ev_silver'), tests.v('clubA'), 'Silver time trial', 'meet',
  tests.today() + 6, tests.today() + 6, p_venue => 'Main pool', p_course => 'scm',
  p_group_ids => array[tests.v('silver')], p_notify => false);
select tests.eq('edit changes the day and marks it updated',
  (select count(*) from public.events where id = tests.v('ev_silver')
     and start_date = tests.today() + 6 and updated_at is not null and updated_by = tests.who('hc1')), 1);
reset role;
select tests.eq('new events wait to notify families',
  (select count(*) from public.event_notifications where reason = 'new' and sent_at is null), 2);
select tests.eq('unticking notify sends nothing for the edit',
  (select count(*) from public.event_notifications where reason = 'updated'), 0);

-- ===== Head coach: an event that cancels training =====
select set_config('request.jwt.claim.sub', tests.who('asst1')::text, false);
set role authenticated;
select tests.set_v('ev_gold', public.save_event(
  null, tests.v('clubA'), 'Gold away meet', 'meet', tests.today() + 30, tests.today() + 31,
  p_course => 'lcm', p_group_ids => array[tests.v('gold')], p_cancel_training => true));
select tests.eq('the event made a rest day for Gold',
  (select count(*) from public.rest_days where event_id = tests.v('ev_gold') and group_id = tests.v('gold')
     and title = 'Gold away meet'), 1);
select tests.eq('Gold training on those days is cancelled',
  (select count(*) from public.sessions where group_id = tests.v('gold') and status = 'scheduled'
     and session_date between tests.today() + 30 and tests.today() + 31), 0);
-- Moving the event moves the rest day.
select public.save_event(tests.v('ev_gold'), tests.v('clubA'), 'Gold away meet', 'meet',
  tests.today() + 40, tests.today() + 41, p_course => 'lcm', p_group_ids => array[tests.v('gold')],
  p_cancel_training => true);
select tests.eq('moved event still has one rest day',
  (select count(*) from public.rest_days where event_id = tests.v('ev_gold')
     and start_date = tests.today() + 40), 1);
select tests.eq('training on the old days is back',
  (select count(*) from public.sessions where group_id = tests.v('gold') and status = 'cancelled'
     and session_date between tests.today() + 30 and tests.today() + 31), 0);
reset role;

-- An assistant can make a small edit without schedule rights...
select set_config('request.jwt.claim.sub', tests.who('hc1')::text, false);
set role authenticated;
select public.save_event(tests.v('ev_gold'), tests.v('clubA'), 'Gold away meet (Cebu)', 'meet',
  tests.today() + 40, tests.today() + 41, p_course => 'lcm', p_group_ids => array[tests.v('gold')],
  p_cancel_training => true);
select tests.eq('small edit keeps the rest day and renames it',
  (select count(*) from public.rest_days where event_id = tests.v('ev_gold') and title = 'Gold away meet (Cebu)'), 1);
-- ...but can't delete it, because that brings Gold training back.
select tests.fails('assistant can''t undo Gold''s cancelled training',
  format('select public.delete_event(%L)', tests.v('ev_gold')));
reset role;

select set_config('request.jwt.claim.sub', tests.who('asst1')::text, false);
set role authenticated;
select public.delete_event(tests.v('ev_gold'));
select tests.eq('deleting the event removes it', (select count(*) from public.events where id = tests.v('ev_gold')), 0);
select tests.eq('...and its rest day', (select count(*) from public.rest_days where title like 'Gold away meet%'), 0);
select tests.eq('...and Gold training is back',
  (select count(*) from public.sessions where group_id = tests.v('gold') and status = 'cancelled'
     and session_date between tests.today() + 40 and tests.today() + 41), 0);
reset role;

-- ===== Families =====
select set_config('request.jwt.claim.sub', tests.who('swim3')::text, false);
set role authenticated;
select tests.eq('Silver swimmer sees the club event and the Silver event',
  (select count(*) from public.swimmer_events(tests.v('dan'), tests.today(), tests.today() + 60)), 2);
select tests.fails('swimmer can''t add events',
  format('select public.save_event(null, %L, ''X'', ''meet'', %L, %L)', tests.v('clubA'), tests.today(), tests.today()));
select tests.fails('swimmer can''t delete events', format('select public.delete_event(%L)', tests.v('ev_club')));
reset role;

select set_config('request.jwt.claim.sub', tests.who('swim2')::text, false);
set role authenticated;
select tests.eq('Gold swimmer sees only the club event',
  (select count(*) from public.swimmer_events(tests.v('ben'), tests.today(), tests.today() + 60)), 1);
reset role;

select set_config('request.jwt.claim.sub', tests.who('par2')::text, false);
set role authenticated;
select tests.eq('parent sees their child''s events',
  (select count(*) from public.swimmer_events(tests.v('dan'), tests.today(), tests.today() + 60)), 2);
select tests.fails('parent can''t see events for another child',
  format('select * from public.swimmer_events(%L, %L, %L)', tests.v('eva'), tests.today(), tests.today() + 60));
reset role;

-- A planned move: Dan moves to Gold before the Silver time trial.
select set_config('request.jwt.claim.sub', tests.who('asst1')::text, false);
set role authenticated;
select public.move_swimmers(array[tests.v('dan')], tests.v('gold'), tests.today() + 3);
reset role;
select set_config('request.jwt.claim.sub', tests.who('swim3')::text, false);
set role authenticated;
select tests.eq('after a planned move, the old group''s later event is gone',
  (select count(*) from public.swimmer_events(tests.v('dan'), tests.today(), tests.today() + 60)), 1);
reset role;

-- ===== Other clubs and the superadmin =====
select set_config('request.jwt.claim.sub', tests.who('hc2')::text, false);
set role authenticated;
select tests.eq('other club sees no events', (select count(*) from public.events), 0);
select tests.fails('other club can''t add events to club A',
  format('select public.save_event(null, %L, ''X'', ''meet'', %L, %L)', tests.v('clubA'), tests.today(), tests.today()));
select tests.fails('other club can''t delete club A''s events', format('select public.delete_event(%L)', tests.v('ev_club')));
reset role;

select set_config('request.jwt.claim.sub', tests.who('miguel')::text, false);
set role authenticated;
select tests.eq('superadmin can read events', (select count(*) from public.events where club_id = tests.v('clubA')), 2);
select tests.fails('superadmin can''t add events',
  format('select public.save_event(null, %L, ''X'', ''meet'', %L, %L)', tests.v('clubA'), tests.today(), tests.today()));
reset role;

\echo 'All events tests passed.'
