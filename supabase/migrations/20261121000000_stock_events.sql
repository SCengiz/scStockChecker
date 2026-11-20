-- Stock history: one row each time a wanted size comes into stock, closed when
-- it sells out again. Replaces the notifications table (an event is what was
-- notified), so the app can show "came in at 14:02, sold out after 6 min".

create table public.stock_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  item_id uuid references public.tracked_items (id) on delete cascade,
  brand text not null,
  product_name text not null,
  color_name text,
  size_name text not null,
  image_url text,
  url text,
  started_at timestamptz not null default now(),
  -- Set when the size is no longer available; null while still in stock.
  ended_at timestamptz,
  notified boolean not null default false
);

create index stock_events_user on public.stock_events (user_id, started_at desc);
create index stock_events_open on public.stock_events (item_id, size_name) where ended_at is null;

alter table public.stock_events enable row level security;
create policy "read own stock events" on public.stock_events
  for select using (user_id = auth.uid());

drop table public.notifications;
