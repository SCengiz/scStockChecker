-- Shared settings, changed from the app. The cron job fires every 10 seconds
-- but only calls check-stock once check_interval_seconds have passed since the
-- last run (see supabase/cron.sql).

create table public.app_settings (
  id integer primary key default 1 check (id = 1),
  check_interval_seconds integer not null default 30 check (check_interval_seconds between 10 and 3600),
  updated_at timestamptz not null default now()
);

insert into public.app_settings (id) values (1);

alter table public.app_settings enable row level security;
create policy "signed-in users read settings" on public.app_settings
  for select to authenticated using (true);
create policy "signed-in users change settings" on public.app_settings
  for update to authenticated using (true) with check (true);
