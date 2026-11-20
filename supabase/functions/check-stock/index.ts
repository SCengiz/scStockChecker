// Run on a schedule (pg_cron, every 30 s). Syncs favourites lists into tracked
// items, checks every active item's stock, records when wanted sizes come in or
// sell out, and sends an ntfy notification when one comes in.
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { type ProductInfo, resolveAdapter } from "../_shared/brands/index.ts";
import { json } from "../_shared/cors.ts";
import { sendNtfy } from "../_shared/ntfy.ts";
import { colorUrl, diffSizes, type ItemRow, pickColor, type StoredSize } from "../_shared/stock.ts";

const WATCHLIST_SYNC_MINUTES = 5;
const CONCURRENCY = 6;

const errorText = (e: unknown) => (e instanceof Error ? e.message : String(e));
const now = () => new Date().toISOString();
const itemKey = (url: string, colorId: string | null) => `${url}|${colorId ?? ""}`;

async function mapLimit<T>(items: T[], limit: number, fn: (item: T) => Promise<void>) {
  const queue = [...items];
  await Promise.all(
    Array.from({ length: Math.min(limit, queue.length) }, async () => {
      for (let next = queue.shift(); next !== undefined; next = queue.shift()) await fn(next);
    }),
  );
}

async function syncWatchlists(db: SupabaseClient): Promise<number> {
  const due = new Date(Date.now() - WATCHLIST_SYNC_MINUTES * 60_000).toISOString();
  const { data: lists, error } = await db
    .from("watchlists")
    .select("id, user_id, url, wanted_sizes")
    .or(`last_synced_at.is.null,last_synced_at.lt.${due}`);
  if (error) throw error;

  let synced = 0;
  await mapLimit(lists ?? [], CONCURRENCY, async (list) => {
    try {
      const { adapter, url } = resolveAdapter(list.url);
      const wishlist = await adapter.fetchWishlist(url);
      const { data: current, error: e1 } = await db
        .from("tracked_items").select("id, url, color_id").eq("watchlist_id", list.id);
      if (e1) throw e1;

      const have = new Set((current ?? []).map((r) => itemKey(r.url, r.color_id)));
      const keep = new Set(wishlist.items.map((it) => itemKey(it.url, it.colorId)));
      const fresh = wishlist.items
        .filter((it) => !have.has(itemKey(it.url, it.colorId)))
        .map((it) => ({
          user_id: list.user_id,
          watchlist_id: list.id,
          brand: wishlist.brand,
          url: it.url,
          color_id: it.colorId,
          wanted_sizes: list.wanted_sizes,
        }));
      const gone = (current ?? []).filter((r) => !keep.has(itemKey(r.url, r.color_id))).map((r) => r.id);

      if (fresh.length) {
        const { error: e2 } = await db.from("tracked_items").insert(fresh);
        if (e2) throw e2;
      }
      if (gone.length) await db.from("tracked_items").delete().in("id", gone);
      await db.from("watchlists")
        .update({ name: wishlist.name, last_synced_at: now(), last_error: null }).eq("id", list.id);
      synced++;
    } catch (e) {
      await db.from("watchlists").update({ last_synced_at: now(), last_error: errorText(e) }).eq("id", list.id);
    }
  });
  return synced;
}

async function checkItems(db: SupabaseClient) {
  const [{ data: items, error }, { data: profiles }] = await Promise.all([
    db.from("tracked_items").select("id, user_id, brand, url, color_id, wanted_sizes, sizes").eq("active", true),
    db.from("profiles").select("user_id, ntfy_topic"),
  ]);
  if (error) throw error;
  const topics = new Map((profiles ?? []).map((p) => [p.user_id, p.ntfy_topic as string | null]));

  // Fetch each product colour once, even if several items/users track it. The
  // colour goes in ?v1= because Zara names the product after the requested colour.
  const groups = new Map<string, ItemRow[]>();
  for (const it of (items ?? []) as ItemRow[]) {
    const key = colorUrl(it.url, it.color_id);
    groups.set(key, [...(groups.get(key) ?? []), it]);
  }

  const stats = { checked: 0, cameIn: 0, failed: 0 };
  await mapLimit([...groups.entries()], CONCURRENCY, async ([url, rows]) => {
    let product: ProductInfo;
    try {
      const { adapter, url: parsed } = resolveAdapter(url);
      product = await adapter.fetchProduct(parsed);
    } catch (e) {
      stats.failed += rows.length;
      await db.from("tracked_items")
        .update({ last_checked_at: now(), last_error: errorText(e) }).in("id", rows.map((r) => r.id));
      return;
    }
    await Promise.all(rows.map((item) => applyResult(db, item, product, topics.get(item.user_id) ?? null, stats)));
  });
  return stats;
}

async function applyResult(
  db: SupabaseClient,
  item: ItemRow,
  product: ProductInfo,
  topic: string | null,
  stats: { checked: number; cameIn: number },
) {
  const color = pickColor(product, item.color_id);
  const sizes: StoredSize[] = (color?.sizes ?? []).map((s) => ({ name: s.name, availability: s.availability }));
  const { cameIn, wentOut } = diffSizes(item, sizes);

  await db.from("tracked_items").update({
    external_id: product.externalId,
    name: product.name,
    color_id: color?.id ?? item.color_id,
    color_name: color?.name ?? null,
    image_url: color?.imageUrl ?? null,
    price: color?.price ?? null,
    currency: product.currency,
    sizes,
    last_checked_at: now(),
    last_error: null,
  }).eq("id", item.id);
  stats.checked++;

  if (wentOut.length) {
    await db.from("stock_events").update({ ended_at: now() })
      .eq("item_id", item.id).is("ended_at", null).in("size_name", wentOut);
  }
  if (!cameIn.length) return;
  stats.cameIn += cameIn.length;

  const link = colorUrl(product.url, color?.id ?? null);
  let notified = false;
  if (topic) {
    const brand = product.brand.charAt(0).toUpperCase() + product.brand.slice(1);
    try {
      await sendNtfy({
        topic,
        title: `${brand}: ${product.name}`,
        message: `${cameIn.join(", ")} stokta!${color ? ` (${color.name})` : ""}`,
        click: link,
        imageUrl: color?.imageUrl,
      });
      notified = true;
    } catch (e) {
      console.error("ntfy failed", item.id, errorText(e));
    }
  }
  await db.from("stock_events").insert(cameIn.map((size) => ({
    user_id: item.user_id,
    item_id: item.id,
    brand: product.brand,
    product_name: product.name,
    color_name: color?.name ?? null,
    size_name: size,
    image_url: color?.imageUrl ?? null,
    url: link,
    notified,
  })));
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) return json({ error: "unauthorized" }, 401);

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const started = new Date();
  let result: { synced: number; checked: number; cameIn: number; failed: number } | null = null;
  let error: string | null = null;
  try {
    const synced = await syncWatchlists(db);
    result = { synced, ...(await checkItems(db)) };
  } catch (e) {
    error = errorText(e);
    console.error(error);
  }
  const ms = Date.now() - started.getTime();
  await Promise.all([
    db.from("check_runs").insert({
      started_at: started.toISOString(),
      duration_ms: ms,
      lists_synced: result?.synced ?? 0,
      items_checked: result?.checked ?? 0,
      items_failed: result?.failed ?? 0,
      came_in: result?.cameIn ?? 0,
      error,
    }),
    db.from("check_runs").delete().lt("started_at", new Date(Date.now() - 86_400_000).toISOString()),
  ]);
  return error ? json({ error, ms }, 500) : json({ ...result, ms });
});
