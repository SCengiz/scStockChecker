-- One row per check-stock run, so the app can show that checking is alive.
-- Kept for 24 hours (the function prunes older rows).

create table public.check_runs (
  id bigint generated always as identity primary key,
  started_at timestamptz not null default now(),
  duration_ms integer not null,
  lists_synced integer not null default 0,
  items_checked integer not null default 0,
  items_failed integer not null default 0,
  came_in integer not null default 0,
  error text
);

create index check_runs_started on public.check_runs (started_at desc);

alter table public.check_runs enable row level security;
create policy "signed-in users read runs" on public.check_runs
  for select to authenticated using (true);
