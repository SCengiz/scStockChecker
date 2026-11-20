-- scStockChecker schema

-- One row per user: where to send notifications.
create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  -- Secret ntfy.sh topic name the user subscribes to in the ntfy iOS app.
  ntfy_topic text,
  created_at timestamptz not null default now()
);

-- Brand favourites / wishlists. Their products are synced into tracked_items.
create table public.watchlists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  brand text not null,
  url text not null,
  name text,
  -- Sizes (by name, e.g. 'M', '38') to watch for every product in this list.
  wanted_sizes text[] not null default '{}',
  last_synced_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  unique (user_id, url)
);

-- One row per product colour the user tracks.
create table public.tracked_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  -- Set when the item came from a watchlist; removed together with it.
  watchlist_id uuid references public.watchlists (id) on delete cascade,
  brand text not null,
  url text not null,
  external_id text,
  name text,
  color_id text,
  color_name text,
  image_url text,
  price numeric,
  currency text,
  -- Sizes (by name) the user wants to be notified about.
  wanted_sizes text[] not null default '{}',
  -- Latest availability per size: [{"name":"M","availability":"in_stock"}, ...]
  sizes jsonb not null default '[]',
  active boolean not null default true,
  last_checked_at timestamptz,
  last_error text,
  created_at timestamptz not null default now()
);

create unique index tracked_items_user_product_color
  on public.tracked_items (user_id, url, coalesce(color_id, ''));
create index tracked_items_active on public.tracked_items (active, last_checked_at);

-- Every notification sent, so the app can show history.
create table public.notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  item_id uuid references public.tracked_items (id) on delete set null,
  title text not null,
  body text not null,
  url text,
  sent_at timestamptz not null default now()
);
create index notifications_user on public.notifications (user_id, sent_at desc);

-- Row level security: each user sees only their own rows.
alter table public.profiles enable row level security;
alter table public.watchlists enable row level security;
alter table public.tracked_items enable row level security;
alter table public.notifications enable row level security;

create policy "own profile" on public.profiles
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own watchlists" on public.watchlists
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own items" on public.tracked_items
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "read own notifications" on public.notifications
  for select using (user_id = auth.uid());

-- Create a profile automatically for every new user.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
