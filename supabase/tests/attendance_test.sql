-- Checks the attendance rules (runs after schedule_test.sql and reuses its
-- people, clubs and helpers).
-- At this point in club A: asst1 is head coach, hc1 is an assistant with no
-- switches, Ben (login swim2) has a Gold/Bronze schedule.
\set ON_ERROR_STOP 1
\set QUIET 1
set client_min_messages = notice;

-- ===== Set up (as the database owner) =====
-- Two Silver swimmers who joined a month ago: Dan (own login swim3, parent
-- par2) and Eva. Plus Silver sessions in the past, today and the future,
-- written directly so the tests work on any day of the week.
select tests.add_person(n) from unnest(array['swim3', 'par2']) n;
insert into public.swimmers (club_id, first_name, last_name, birth_date, gender, current_group_id, joined_on)
values (tests.v('clubA'), 'Dan', 'Lim', '2012-01-10', 'male', tests.v('silver'), tests.today() - 30),
       (tests.v('clubA'), 'Eva', 'Tan', '2013-03-11', 'female', tests.v('silver'), tests.today() - 30);
select tests.set_v('dan', (select id from public.swimmers where first_name = 'Dan'));
select tests.set_v('eva', (select id from public.swimmers where first_name = 'Eva'));
update public.swimmers set user_id = tests.who('swim3') where id = tests.v('dan');
insert into public.club_members (club_id, user_id, role) values
  (tests.v('clubA'), tests.who('swim3'), 'swimmer'),
  (tests.v('clubA'), tests.who('par2'), 'parent');
insert into public.parent_links (club_id, swimmer_id, parent_user_id)
values (tests.v('clubA'), tests.v('dan'), tests.who('par2'));

insert into public.sessions (club_id, group_id, session_date, start_time, end_time, label, status) values
  (tests.v('clubA'), tests.v('silver'), tests.today(),      '05:00', '06:00', 'T today',     'scheduled'),
  (tests.v('clubA'), tests.v('silver'), tests.today() - 3,  '05:00', '06:00', 'T recent',    'scheduled'),
  (tests.v('clubA'), tests.v('silver'), tests.today() - 10, '05:00', '06:00', 'T old',       'scheduled'),
  (tests.v('clubA'), tests.v('silver'), tests.today() + 2,  '05:00', '06:00', 'T future',    'scheduled'),
  (tests.v('clubA'), tests.v('silver'), tests.today() - 1,  '05:00', '06:00', 'T cancelled', 'cancelled');
select tests.set_v('s_today',     (select id from public.sessions where label = 'T today'));
select tests.set_v('s_recent',    (select id from public.sessions where label = 'T recent'));
select tests.set_v('s_old',       (select id from public.sessions where label = 'T old'));
select tests.set_v('s_future',    (select id from public.sessions where label = 'T future'));
select tests.set_v('s_cancelled', (select id from public.sessions where label = 'T cancelled'));

create function tests.marks(p_pairs text[]) returns jsonb language sql as $$
  -- p_pairs: swimmer var, status, reason, note, ...
  select jsonb_agg(jsonb_build_object(
    'swimmer_id', tests.v(p_pairs[i]), 'status', p_pairs[i + 1],
    'excuse_reason', p_pairs[i + 2], 'note', p_pairs[i + 3]))
  from generate_series(1, cardinality(p_pairs), 4) i
$$;
grant execute on function tests.marks(text[]) to authenticated;

-- ===== An assistant (no switches, not assigned to Silver) takes attendance =====
select set_config('request.jwt.claim.sub', tests.who('hc1')::text, false);
set role authenticated;
select tests.eq('roster lists the swimmers in Silver that day',
  (select count(*) from public.session_roster(tests.v('s_recent'))
    where swimmer_id in (tests.v('dan'), tests.v('eva')) and status is null), 2);
select tests.eq('roster leaves out swimmers from other groups',
  (select count(*) from public.session_roster(tests.v('s_recent')) where swimmer_id = tests.v('ben')), 0);
select tests.eq('assistant saves marks for any group',
  public.save_attendance(tests.v('s_recent'),
    tests.marks(array['dan', 'present', null, null, 'eva', 'excused', 'medical', 'fever'])), 2);
select tests.eq('marks are saved with who and when',
  (select count(*) from public.attendance where session_id = tests.v('s_recent')
     and marked_by = tests.who('hc1') and marked_at is not null), 2);
select tests.eq('roster shows the saved marks and the coach''s name',
  (select count(*) from public.session_roster(tests.v('s_recent'))
    where swimmer_id = tests.v('eva') and status = 'excused' and excuse_reason = 'medical'
      and note = 'fever' and marked_by_name = 'Hc1'), 1);
select tests.fails('excused needs a reason',
  format('select public.save_attendance(%L, %L)', tests.v('s_recent'),
         tests.marks(array['dan', 'excused', null, null])));
select tests.fails('a swimmer from another group can''t be marked',
  format('select public.save_attendance(%L, %L)', tests.v('s_recent'),
         tests.marks(array['ben', 'present', null, null])));
select tests.fails('a future session can''t be marked yet',
  format('select public.save_attendance(%L, %L)', tests.v('s_future'),
         tests.marks(array['dan', 'present', null, null])));
select tests.fails('a cancelled session can''t be marked',
  format('select public.save_attendance(%L, %L)', tests.v('s_cancelled'),
         tests.marks(array['dan', 'present', null, null])));
select tests.fails('an assistant can''t change a session more than 7 days old',
  format('select public.save_attendance(%L, %L)', tests.v('s_old'),
         tests.marks(array['dan', 'present', null, null])));
select tests.fails('cannot write attendance directly',
  format('insert into public.attendance (club_id, session_id, swimmer_id, status) values (%L, %L, %L, ''present'')',
         tests.v('clubA'), tests.v('s_today'), tests.v('dan')));
-- Changing a mark keeps the history.
select public.save_attendance(tests.v('s_recent'), tests.marks(array['dan', 'late', null, null]));
select tests.eq('change history keeps every change',
  (select count(*) from public.attendance_changes where session_id = tests.v('s_recent') and swimmer_id = tests.v('dan')), 2);
select tests.eq('...including the old and new mark',
  (select count(*) from public.attendance_changes where swimmer_id = tests.v('dan')
     and old_status = 'present' and new_status = 'late' and changed_by = tests.who('hc1')), 1);
select public.save_attendance(tests.v('s_recent'), tests.marks(array['dan', 'late', null, null]));
select tests.eq('saving the same mark again adds no history',
  (select count(*) from public.attendance_changes where swimmer_id = tests.v('dan')), 2);
reset role;

-- ===== The head coach can change older sessions =====
select set_config('request.jwt.claim.sub', tests.who('asst1')::text, false);
set role authenticated;
select tests.eq('head coach changes a session more than 7 days old',
  public.save_attendance(tests.v('s_old'), tests.marks(array['dan', 'absent', null, null, 'eva', 'early_up', null, null])), 2);
select public.save_attendance(tests.v('s_today'), tests.marks(array['dan', 'dnf', null, null, 'eva', 'present', null, null]));

-- ===== Sessions with attendance are protected =====
select tests.fails('a session with attendance can''t be cancelled',
  format('select public.cancel_sessions(array[%L]::uuid[])', tests.v('s_today')));
select tests.fails('a rest day can''t cancel a session with attendance',
  format('select public.add_rest_days(%L, array[%L]::uuid[], %L, %L)',
         tests.v('clubA'), tests.v('silver'), tests.today(), tests.today()));
select tests.eq('clear the attendance', public.clear_attendance(tests.v('s_today')), 2);
select tests.eq('...then it can be cancelled', public.cancel_sessions(array[tests.v('s_today')]), 1);
select public.restore_session(tests.v('s_today'));
select public.save_attendance(tests.v('s_today'), tests.marks(array['dan', 'present', null, null]));

-- ===== Coach overview =====
select tests.eq('overview counts the marks per session',
  (select marked from public.club_attendance_overview(tests.v('clubA'), tests.today() - 10, tests.today())
    where session_id = tests.v('s_recent')), 2);
select tests.eq('overview counts the swimmers in the group that day',
  (select swimmers from public.club_attendance_overview(tests.v('clubA'), tests.today() - 10, tests.today())
    where session_id = tests.v('s_recent')), 2);  -- Dan and Eva
select tests.eq('overview shows unmarked sessions with 0',
  (select count(*) from public.club_attendance_overview(tests.v('clubA'), tests.today() - 1, tests.today())
    where session_id = tests.v('s_cancelled') and marked = 0 and status = 'cancelled'), 1);

-- ===== A moved swimmer stays on the old group's past lists =====
select public.move_swimmers(array[tests.v('eva')], tests.v('gold'));
select tests.eq('moved swimmer still on Silver''s past session',
  (select count(*) from public.session_roster(tests.v('s_recent')) where swimmer_id = tests.v('eva')), 1);
select tests.eq('...and not on Silver''s list from the move date',
  (select count(*) from public.session_roster(tests.v('s_today')) where swimmer_id = tests.v('eva')), 0);
reset role;

-- ===== Families =====
select set_config('request.jwt.claim.sub', tests.who('swim3')::text, false);
set role authenticated;
select tests.eq('swimmer sees their own marks',
  (select count(*) from public.swimmer_attendance(tests.v('dan'), tests.today() - 30, tests.today())), 3);
select tests.eq('...without coach notes',
  (select count(*) from public.swimmer_attendance(tests.v('dan'), tests.today() - 30, tests.today()) where note is not null), 0);
select tests.eq('swimmer can''t read the attendance table directly', (select count(*) from public.attendance), 0);
select tests.fails('swimmer can''t read a teammate''s attendance',
  format('select * from public.swimmer_attendance(%L, %L, %L)', tests.v('eva'), tests.today() - 30, tests.today()));
select tests.fails('swimmer can''t take attendance',
  format('select public.save_attendance(%L, %L)', tests.v('s_recent'), tests.marks(array['dan', 'present', null, null])));
select tests.fails('swimmer can''t see the roster',
  format('select * from public.session_roster(%L)', tests.v('s_recent')));
reset role;

select set_config('request.jwt.claim.sub', tests.who('par2')::text, false);
set role authenticated;
select tests.eq('parent sees their child''s marks',
  (select count(*) from public.swimmer_attendance(tests.v('dan'), tests.today() - 30, tests.today())), 3);
select tests.fails('parent can''t see another child''s marks',
  format('select * from public.swimmer_attendance(%L, %L, %L)', tests.v('eva'), tests.today() - 30, tests.today()));
reset role;

select set_config('request.jwt.claim.sub', tests.who('hc2')::text, false);
set role authenticated;
select tests.eq('other club sees no attendance', (select count(*) from public.attendance), 0);
select tests.fails('other club can''t read club A''s marks',
  format('select * from public.swimmer_attendance(%L, %L, %L)', tests.v('dan'), tests.today() - 30, tests.today()));
select tests.fails('other club can''t take club A''s attendance',
  format('select public.save_attendance(%L, %L)', tests.v('s_recent'), tests.marks(array['dan', 'present', null, null])));
reset role;

-- ===== Superadmin reads but can't change =====
select set_config('request.jwt.claim.sub', tests.who('miguel')::text, false);
set role authenticated;
select tests.ok('superadmin can read the roster',
  (select count(*) from public.session_roster(tests.v('s_recent'))) > 0);
select tests.fails('superadmin can''t take attendance',
  format('select public.save_attendance(%L, %L)', tests.v('s_recent'), tests.marks(array['dan', 'present', null, null])));
reset role;

-- ===== Scoring =====
select tests.eq('present = 1, late/early-up/DNF = half, absent = 0, excused not counted',
  (select (sum(public.attendance_points(s)) * 10)::bigint
     from unnest(array['present', 'late', 'early_up', 'dnf', 'absent', 'excused']::public.attendance_status[]) s), 25);

\echo 'All attendance tests passed.'
