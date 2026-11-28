-- Checks the coach dashboard's attendance summary (runs after
-- attendance_test.sql and reuses its swimmers and marks).
-- At this point Dan has Silver marks: Late (3 days ago), Absent (10 days
-- ago) and Present (today). Eva has Silver marks Excused and Early-Up,
-- and has since moved up to Gold.
\set ON_ERROR_STOP 1
\set QUIET 1
set client_min_messages = notice;

-- ===== A coach of the club =====
select set_config('request.jwt.claim.sub', tests.who('hc1')::text, false);
set role authenticated;
select tests.eq('one row per swimmer and group',
  (select count(*) from public.club_attendance_summary(tests.v('clubA'), tests.today() - 30, tests.today())
    where swimmer_id in (tests.v('dan'), tests.v('eva'))), 2);
select tests.eq('counts each kind of mark',
  (select count(*) from public.club_attendance_summary(tests.v('clubA'), tests.today() - 30, tests.today())
    where swimmer_id = tests.v('dan') and group_id = tests.v('silver')
      and present = 1 and late = 1 and absent = 1 and early_up = 0 and dnf = 0 and excused = 0), 1);
select tests.eq('a moved swimmer''s old marks stay with the old group, with their current group alongside',
  (select count(*) from public.club_attendance_summary(tests.v('clubA'), tests.today() - 30, tests.today())
    where swimmer_id = tests.v('eva') and group_id = tests.v('silver')
      and current_group_id = tests.v('gold') and current_group_name = 'Gold' and excused = 1 and early_up = 1), 1);
select tests.eq('only sessions inside the dates count',
  (select coalesce(sum(present + late + early_up + dnf + absent + excused), 0)
     from public.club_attendance_summary(tests.v('clubA'), tests.today() - 5, tests.today())
    where swimmer_id = tests.v('dan')), 2);
select tests.fails('at most one year',
  format('select * from public.club_attendance_summary(%L, %L, %L)', tests.v('clubA'), tests.today() - 400, tests.today()));
reset role;

-- ===== Families, other clubs and the superadmin =====
select set_config('request.jwt.claim.sub', tests.who('swim3')::text, false);
set role authenticated;
select tests.fails('a swimmer can''t see the club summary',
  format('select * from public.club_attendance_summary(%L, %L, %L)', tests.v('clubA'), tests.today() - 30, tests.today()));
reset role;

select set_config('request.jwt.claim.sub', tests.who('par2')::text, false);
set role authenticated;
select tests.fails('a parent can''t see the club summary',
  format('select * from public.club_attendance_summary(%L, %L, %L)', tests.v('clubA'), tests.today() - 30, tests.today()));
reset role;

select set_config('request.jwt.claim.sub', tests.who('hc2')::text, false);
set role authenticated;
select tests.fails('another club''s coach can''t see club A''s summary',
  format('select * from public.club_attendance_summary(%L, %L, %L)', tests.v('clubA'), tests.today() - 30, tests.today()));
reset role;

select set_config('request.jwt.claim.sub', tests.who('miguel')::text, false);
set role authenticated;
select tests.ok('superadmin can read the summary',
  (select count(*) from public.club_attendance_summary(tests.v('clubA'), tests.today() - 30, tests.today())) > 0);
reset role;

\echo 'All attendance summary tests passed.'
