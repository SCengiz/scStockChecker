-- Check-frequency groups ("Normal", "Öncelikli", plus any the users add).
-- Each item belongs to one group (null = Normal). With auto_priority on, an
-- item also gets the Öncelikli rate while it is "hot" (coming soon, just sold
-- out, usual restock hour), whichever is faster.

create table public.check_tiers (
  id uuid primary key default gen_random_uuid(),
  -- 'normal' and 'priority' are built in (cannot be deleted); null for custom groups.
  key text unique check (key in ('normal', 'priority')),
  name text not null check (length(trim(name)) > 0),
  interval_seconds integer not null check (interval_seconds between 10 and 86400),
  created_at timestamptz not null default now()
);

insert into public.check_tiers (key, name, interval_seconds)
select 'normal', 'Normal', check_interval_seconds from public.app_settings where id = 1
union all
select 'priority', 'Öncelikli', hot_interval_seconds from public.app_settings where id = 1;

alter table public.check_tiers enable row level security;
create policy "signed-in users read tiers" on public.check_tiers
  for select to authenticated using (true);
create policy "signed-in users add tiers" on public.check_tiers
  for insert to authenticated with check (key is null);
create policy "signed-in users change tiers" on public.check_tiers
  for update to authenticated using (true) with check (true);
create policy "signed-in users delete custom tiers" on public.check_tiers
  for delete to authenticated using (key is null);

-- Built-in groups keep their key.
create function public.protect_tier_key() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.key := old.key;
  return new;
end;
$$;
create trigger check_tiers_keep_key before update on public.check_tiers
  for each row execute function public.protect_tier_key();

alter table public.tracked_items
  add column tier_id uuid references public.check_tiers (id) on delete set null,
  add column auto_priority boolean not null default true;

-- Intervals now live in check_tiers. backoff_until pauses all checks after the
-- brand starts blocking us (HTTP 403/429 or a bot-protection page).
alter table public.app_settings
  drop column check_interval_seconds,
  drop column hot_interval_seconds,
  add column backoff_until timestamptz,
  add column backoff_reason text;

-- Load limiting, written by check-stock for the app to show: requests per
-- minute the current settings would need, and how much normal intervals are
-- stretched to stay under the budget (1 = not stretched).
alter table public.app_settings
  add column load_per_minute numeric not null default 0,
  add column load_stretch numeric not null default 1;

-- No "checks stopped" alarm while checks are paused on purpose after a block.
create or replace function public.health_check() returns void
language plpgsql security definer set search_path = '' as $$
declare
  last_run timestamptz;
  topic text;
begin
  if exists (select 1 from public.app_settings where id = 1 and backoff_until > now()) then
    return;
  end if;
  select max(started_at) into last_run from public.check_runs;
  if last_run is not null and last_run > now() - interval '3 minutes' then
    return;
  end if;
  if exists (select 1 from public.app_settings
             where id = 1 and last_health_alert_at > now() - interval '1 hour') then
    return;
  end if;
  update public.app_settings set last_health_alert_at = now() where id = 1;
  for topic in select ntfy_topic from public.profiles where coalesce(ntfy_topic, '') <> '' loop
    perform net.http_post(
      url := 'https://ntfy.sh',
      body := jsonb_build_object(
        'topic', topic,
        'title', 'Stok Takip: kontroller durdu',
        'message', 'Son kontrol: ' || coalesce(to_char(last_run at time zone 'Europe/Istanbul', 'HH24:MI'), 'yok')
                   || '. Uygulamadaki Log sekmesine bakın.',
        'tags', jsonb_build_array('warning'),
        'priority', 4
      ),
      headers := '{"Content-Type": "application/json"}'::jsonb
    );
  end loop;
end;
$$;
revoke execute on function public.health_check() from public, anon, authenticated;
