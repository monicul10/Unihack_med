-- Allow degree 0 = "no burn" (the 7-question triage can conclude there is no burn).
-- Run once in Supabase Dashboard > SQL Editor. Safe to run more than once.
alter table public.scans drop constraint if exists scans_degree_check;
alter table public.scans add constraint scans_degree_check check (degree between 0 and 3);
