-- Row Level Security for public."Incidente".
-- Run once in the Supabase SQL Editor.
--
-- IMPORTANT: the table already has policies of unknown content. Any
-- pre-existing permissive SELECT policy (for example one using (true))
-- must be dropped, otherwise users can read each other's rows. Policies
-- are OR-combined, so one permissive policy defeats the ones below.
-- Run the query in step 1 first, then drop every policy you do not want
-- with:  drop policy "<policyname>" on public."Incidente";

-- 1) List current policies on the table.
select policyname, cmd, qual, with_check
from pg_policies
where tablename = 'Incidente';

-- 2) Enable RLS.
alter table public."Incidente" enable row level security;

-- 3) Users can read only their own rows.
drop policy if exists "incidente_select_own" on public."Incidente";
create policy "incidente_select_own"
  on public."Incidente"
  for select
  to authenticated
  using (auth.uid() = user_id);

-- 4) Users can insert only rows that belong to them.
drop policy if exists "incidente_insert_own" on public."Incidente";
create policy "incidente_insert_own"
  on public."Incidente"
  for insert
  to authenticated
  with check (auth.uid() = user_id);
