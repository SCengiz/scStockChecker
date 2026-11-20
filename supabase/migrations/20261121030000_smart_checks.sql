-- Smarter checking: per-item schedule (hot items more often), more event
-- kinds (coming soon, price drop) and a health alarm when checks stop.

-- Per-item schedule. check-stock only checks items whose next_check_at is due.
alter table public.tracked_items
  add column next_check_at timestamptz,
  -- Why the item is checked at the fast rate right now (null = normal rate).
  add column hot_reason text,
  -- Last successful check; used for the "checks are failing" alarm.
  add column last_ok_at timestamptz;
create index tracked_items_due on public.tracked_items (next_check_at) where active;

alter table public.stock_events
  add column kind text not null default 'in_stock'
    check (kind in ('in_stock', 'coming_soon', 'price_drop')),
  add column price numeric,
  add column old_price numeric;

alter table public.app_settings
  -- Rate for hot items: a wanted size is "coming soon", sold out in the last
  -- hour, or it is the hour of day the item came in before.
  add column hot_interval_seconds integer not null default 10 check (hot_interval_seconds between 10 and 3600),
  add column last_health_alert_at timestamptz;

-- Sends an ntfy alert to every user when no check has run for 3 minutes.
-- Called by its own cron job, so it still fires when check-stock is broken.
create function public.health_check() returns void
language plpgsql security definer set search_path = '' as $$
declare
  last_run timestamptz;
  topic text;
begin
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
                   || '. Uygulamadaki Kontroller ekranına bakın.',
        'tags', jsonb_build_array('warning'),
        'priority', 4
      ),
      headers := '{"Content-Type": "application/json"}'::jsonb
    );
  end loop;
end;
$$;
revoke execute on function public.health_check() from public, anon, authenticated;
