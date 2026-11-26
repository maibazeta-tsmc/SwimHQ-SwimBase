-- =====================================================================
-- SwimBase update: apply scheduled group moves automatically
-- =====================================================================
-- Plain-English summary:
--   When a coach moves a swimmer "starting 1 Dec", the move waits until
--   that date. This turns on Supabase's built-in scheduler (pg_cron) and
--   asks it to apply any moves that are due, every hour, at 5 minutes past.
--   Each club's own timezone decides when "today" starts.
--
-- Safe to run more than once.
-- =====================================================================

do $migration$
begin
  -- The scheduler exists on Supabase. The automatic tests use a plain
  -- database without it, so they skip this step.
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    raise notice 'pg_cron is not available here; skipping the schedule.';
    return;
  end if;

  create extension if not exists pg_cron;

  -- Scheduling under the same name again just updates the job.
  perform cron.schedule(
    'apply-scheduled-moves',
    '5 * * * *',
    'select public.apply_scheduled_moves()'
  );
end
$migration$;
