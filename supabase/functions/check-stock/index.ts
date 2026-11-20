// Run on a schedule (pg_cron). Syncs favourites lists into tracked items, checks
// every active item's stock and sends an ntfy notification when a wanted size
// comes back in stock.
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { type ProductInfo, resolveAdapter } from "../_shared/brands/index.ts";
import { json } from "../_shared/cors.ts";
import { sendNtfy } from "../_shared/ntfy.ts";
import { type ItemRow, newlyAvailable, pickColor, type StoredSize } from "../_shared/stock.ts";

const WATCHLIST_SYNC_MINUTES = 30;
const CONCURRENCY = 3;

const errorText = (e: unknown) => (e instanceof Error ? e.message : String(e));

async function mapLimit<T>(items: T[], limit: number, fn: (item: T) => Promise<void>) {
  const queue = [...items];
  await Promise.all(
    Array.from({ length: Math.min(limit, queue.length) }, async () => {
      for (let next = queue.shift(); next !== undefined; next = queue.shift()) await fn(next);
    }),
  );
}

async function syncWatchlists(db: SupabaseClient) {
  const due = new Date(Date.now() - WATCHLIST_SYNC_MINUTES * 60_000).toISOString();
  const { data: lists, error } = await db
    .from("watchlists")
    .select("id, user_id, url, wanted_sizes")
    .or(`last_synced_at.is.null,last_synced_at.lt.${due}`);
  if (error) throw error;

  let synced = 0;
  for (const list of lists ?? []) {
    try {
      const { adapter, url } = resolveAdapter(list.url);
      const wishlist = await adapter.fetchWishlist(url);
      const rows = wishlist.items.map((it) => ({
        user_id: list.user_id,
        watchlist_id: list.id,
        brand: wishlist.brand,
        url: it.url,
        color_id: it.colorId,
        wanted_sizes: list.wanted_sizes,
      }));
      // Add new products; keep existing rows (and their stock history) as they are.
      if (rows.length) {
        const { data: existing } = await db
          .from("tracked_items").select("url, color_id").eq("watchlist_id", list.id);
        const have = new Set((existing ?? []).map((r) => `${r.url}|${r.color_id ?? ""}`));
        const fresh = rows.filter((r) => !have.has(`${r.url}|${r.color_id ?? ""}`));
        if (fresh.length) {
          const { error: e } = await db.from("tracked_items").insert(fresh);
          if (e) throw e;
        }
      }
      // Remove products that are no longer in the list.
      const keep = new Set(rows.map((r) => `${r.url}|${r.color_id ?? ""}`));
      const { data: current } = await db
        .from("tracked_items").select("id, url, color_id").eq("watchlist_id", list.id);
      const gone = (current ?? []).filter((r) => !keep.has(`${r.url}|${r.color_id ?? ""}`)).map((r) => r.id);
      if (gone.length) await db.from("tracked_items").delete().in("id", gone);

      await db.from("watchlists").update({
        name: wishlist.name, last_synced_at: new Date().toISOString(), last_error: null,
      }).eq("id", list.id);
      synced++;
    } catch (e) {
      await db.from("watchlists").update({
        last_synced_at: new Date().toISOString(), last_error: errorText(e),
      }).eq("id", list.id);
    }
  }
  return synced;
}

async function checkItems(db: SupabaseClient) {
  const { data: items, error } = await db
    .from("tracked_items")
    .select("id, user_id, url, color_id, name, wanted_sizes, sizes")
    .eq("active", true);
  if (error) throw error;

  const { data: profiles } = await db.from("profiles").select("user_id, ntfy_topic");
  const topics = new Map((profiles ?? []).map((p) => [p.user_id, p.ntfy_topic as string | null]));

  // Fetch each product colour once, even if several items/users track it. The
  // colour goes in ?v1= because Zara names the product after the requested colour.
  const byUrl = new Map<string, ItemRow[]>();
  for (const it of (items ?? []) as ItemRow[]) {
    const u = new URL(it.url);
    if (it.color_id) u.searchParams.set("v1", it.color_id);
    const key = u.toString();
    byUrl.set(key, [...(byUrl.get(key) ?? []), it]);
  }

  let checked = 0, notified = 0, failed = 0;
  await mapLimit([...byUrl.entries()], CONCURRENCY, async ([url, rows]) => {
    let product: ProductInfo;
    try {
      const { adapter, url: parsed } = resolveAdapter(url);
      product = await adapter.fetchProduct(parsed);
    } catch (e) {
      failed += rows.length;
      await db.from("tracked_items").update({
        last_checked_at: new Date().toISOString(), last_error: errorText(e),
      }).in("id", rows.map((r) => r.id));
      return;
    }

    for (const item of rows) {
      const color = pickColor(product, item.color_id);
      const sizes: StoredSize[] = (color?.sizes ?? []).map((s) => ({ name: s.name, availability: s.availability }));
      const back = newlyAvailable(item, sizes);

      await db.from("tracked_items").update({
        external_id: product.externalId,
        name: product.name,
        color_id: color?.id ?? item.color_id,
        color_name: color?.name ?? null,
        image_url: color?.imageUrl ?? null,
        price: color?.price ?? null,
        currency: product.currency,
        sizes,
        last_checked_at: new Date().toISOString(),
        last_error: null,
      }).eq("id", item.id);
      checked++;

      if (back.length === 0) continue;
      const brand = product.brand.charAt(0).toUpperCase() + product.brand.slice(1);
      const title = `${brand}: ${product.name}`;
      const body = `${back.join(", ")} beden${back.length > 1 ? "leri" : "i"} stokta!${color ? ` (${color.name})` : ""}`;
      const click = color ? `${product.url}?v1=${color.id}` : product.url;
      const topic = topics.get(item.user_id);
      try {
        if (topic) await sendNtfy({ topic, title, message: body, click, imageUrl: color?.imageUrl });
        await db.from("notifications").insert({ user_id: item.user_id, item_id: item.id, title, body, url: click });
        notified++;
      } catch (e) {
        console.error("notify failed", item.id, errorText(e));
      }
    }
  });
  return { checked, notified, failed };
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) return json({ error: "unauthorized" }, 401);

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  try {
    const synced = await syncWatchlists(db);
    const result = await checkItems(db);
    console.log(JSON.stringify({ synced, ...result }));
    return json({ synced, ...result });
  } catch (e) {
    console.error(errorText(e));
    return json({ error: errorText(e) }, 500);
  }
});
