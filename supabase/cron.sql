-- Run once in the Supabase SQL editor after deploying check-stock.
-- Replace <project-ref> and <cron-secret> (the same value as the CRON_SECRET function secret).
-- Not a migration on purpose: it contains a secret and must not be committed filled in.

create extension if not exists pg_cron;
create extension if not exists pg_net;

select vault.create_secret('<cron-secret>', 'check_stock_cron_secret');

select cron.schedule(
  'check-stock',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := 'https://<project-ref>.supabase.co/functions/v1/check-stock',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'check_stock_cron_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
  $$
);
