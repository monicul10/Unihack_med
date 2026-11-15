-- Scan history: store each analysis result and keep every user's photos private.
-- Run once in Supabase Dashboard > SQL Editor (or `supabase db push`).
-- Safe to run more than once.

-- 1. New columns on scans --------------------------------------------------
alter table public.scans add column if not exists image_path  text;        -- path inside burn_photos: <user_id>/<file>
alter table public.scans add column if not exists degree      smallint check (degree between 1 and 3); -- null = not analyzed
alter table public.scans add column if not exists probability real     check (probability between 0 and 1);
alter table public.scans add column if not exists created_at  timestamptz not null default now();

-- New rows only store image_path (public URLs stop working once the bucket is private).
alter table public.scans alter column image_url drop not null;

-- Old rows: take the storage path from the old public URL ...
update public.scans
set image_path = split_part(image_url, '/burn_photos/', 2)
where image_path is null and image_url like '%/burn_photos/%';

-- ... and the real upload date from the file name (<milliseconds since epoch>.<ext>).
update public.scans
set created_at = to_timestamp(substring(image_path from '/(\d{13})\.[A-Za-z]+$')::bigint / 1000.0)
where image_path ~ '/\d{13}\.[A-Za-z]+$';

create index if not exists scans_user_created_idx on public.scans (user_id, created_at desc);

-- 2. Users can only read and add their own scans ----------------------------
alter table public.scans enable row level security;

drop policy if exists "scans: owner can read" on public.scans;
create policy "scans: owner can read" on public.scans
  for select to authenticated
  using ((select auth.uid())::text = user_id::text);

drop policy if exists "scans: owner can insert" on public.scans;
create policy "scans: owner can insert" on public.scans
  for insert to authenticated
  with check ((select auth.uid())::text = user_id::text);

-- 3. Private bucket: photos only through signed URLs, only for the owner -----
update storage.buckets set public = false where id = 'burn_photos';

drop policy if exists "burn_photos: owner can read" on storage.objects;
create policy "burn_photos: owner can read" on storage.objects
  for select to authenticated
  using (bucket_id = 'burn_photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "burn_photos: owner can upload" on storage.objects;
create policy "burn_photos: owner can upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'burn_photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- 4. CHECK AFTER RUNNING: policies are combined with OR, so an older, broader policy
-- (for example "allow all users to read") would still let users see others' data.
-- Run this and remove any old policy on scans or burn_photos that doesn't check the owner:
--
--   select tablename, policyname, cmd, roles, qual, with_check
--   from pg_policies
--   where (schemaname = 'public' and tablename = 'scans')
--      or (schemaname = 'storage' and tablename = 'objects');
