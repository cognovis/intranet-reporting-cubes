
SELECT acs_log__debug('/packages/intranet-reporting-cubes/sql/postgresql/upgrade/upgrade-4.0.4.0.0-4.0.4.0.1.sql','');

-- Fix the URL of the timesheet cube
update im_menus
set url = '/intranet-reporting-cubes/timesheet-cube?'
where label = 'reporting-timesheet-cube';

