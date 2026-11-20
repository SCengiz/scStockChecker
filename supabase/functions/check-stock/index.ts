// Called by pg_cron every 10 s while something is due. Syncs favourites lists
// into tracked items, checks the items whose next_check_at has come, records
// stock changes (in stock / sold out / coming soon / price drop), notifies via
// ntfy, and schedules each item's next check from its frequency group
// (check_tiers); with auto_priority, "hot" items get the Öncelikli rate.
// When the brand starts blocking us, all checks pause for BACKOFF_MINUTES.
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { BrandError, type ProductInfo, resolveAdapter } from "../_shared/brands/index.ts";
import { json } from "../_shared/cors.ts";
import { type Notification, sendNtfy } from "../_shared/ntfy.ts";
import {
  colorUrl,
  diffSizes,
  hotReason,
  istanbulHour,
  type ItemRow,
  pickColor,
  type StoredSize,
  wantedComingSoon,
} from "../_shared/stock.ts";

const WATCHLIST_SYNC_MINUTES = 5;
const CONCURRENCY = 6;
/** Alert when an item has not been read successfully for this long. */
const FAILING_ALERT_MINUTES = 10;
/** Pause after the brand answers 403/429 or with a bot-protection page. */
const BACKOFF_MINUTES = 5;
/**
 * Most product requests per minute we send to a brand. When the configured
 * intervals would need more, normal items are stretched first (priority
 * items keep their rate while they fit in the budget).
 */
export const MAX_REQUESTS_PER_MINUTE = 30;

type Db = SupabaseClient;
interface Settings {
  /** Interval of the built-in Normal group (items without a group). */
  normal: number;
  /** Interval of the built-in Öncelikli group (used for hot items). */
  priority: number;
  tiers: Map<string, number>;
  lastHealthAlert: Date | null;
  backoffUntil: Date | null;
  /** Multipliers keeping the load inside MAX_REQUESTS_PER_MINUTE (1 = no stretch). */
  stretch: { priority: number; normal: number };
}
interface Item extends ItemRow {
  price: number | null;
  last_ok_at: string | null;
  tier_id: string | null;
  auto_priority: boolean;
}
interface History {
  lastSoldOut: Date | null;
  restockHours: Set<number>;
}
type Stats = { checked: number; failed: number; cameIn: number; hot: number; blocked: string | null };

const errorText = (e: unknown) => (e instanceof Error ? e.message : String(e));
const iso = (d = new Date()) => d.toISOString();
const itemKey = (url: string, colorId: string | null) => `${url}|${colorId ?? ""}`;
const brandName = (b: string) => b.charAt(0).toUpperCase() + b.slice(1);
const money = (p: number | null, currency: string | null) =>
  p == null ? "" : new Intl.NumberFormat("tr-TR", { style: "currency", currency: currency ?? "TRY" }).format(p);

async function mapLimit<T>(items: T[], limit: number, fn: (item: T) => Promise<void>) {
  const queue = [...items];
  await Promise.all(
    Array.from({ length: Math.min(limit, queue.length) }, async () => {
      for (let next = queue.shift(); next !== undefined; next = queue.shift()) await fn(next);
    }),
  );
}

async function loadSettings(db: Db): Promise<Settings> {
  const [{ data: app }, { data: tiers }] = await Promise.all([
    db.from("app_settings").select("last_health_alert_at, backoff_until").eq("id", 1).single(),
    db.from("check_tiers").select("id, key, interval_seconds"),
  ]);
  const byKey = (k: string) => tiers?.find((t) => t.key === k)?.interval_seconds;
  return {
    normal: byKey("normal") ?? 30,
    priority: byKey("priority") ?? 10,
    tiers: new Map((tiers ?? []).map((t) => [t.id, t.interval_seconds])),
    lastHealthAlert: app?.last_health_alert_at ? new Date(app.last_health_alert_at) : null,
    backoffUntil: app?.backoff_until ? new Date(app.backoff_until) : null,
    stretch: { priority: 1, normal: 1 },
  };
}

/** Seconds between checks before load limiting: the group's interval, or the Öncelikli rate while hot. */
function rawInterval(item: Pick<Item, "tier_id" | "auto_priority">, hot: boolean, s: Settings): number {
  const base = (item.tier_id && s.tiers.get(item.tier_id)) || s.normal;
  return hot && item.auto_priority ? Math.min(base, s.priority) : base;
}

function intervalFor(item: Item, hot: boolean, s: Settings): number {
  const raw = rawInterval(item, hot, s);
  return Math.round(raw * (raw <= s.priority ? s.stretch.priority : s.stretch.normal));
}

/**
 * Work out how much to stretch intervals so that all active items together stay
 * under MAX_REQUESTS_PER_MINUTE. Products tracked several times count once
 * (at their fastest rate). Saves the result so the app can show it.
 */
async function planLoad(db: Db, s: Settings): Promise<void> {
  const { data } = await db.from("tracked_items")
    .select("url, color_id, tier_id, auto_priority, hot_reason").eq("active", true);
  const fastest = new Map<string, number>();
  for (const it of data ?? []) {
    const key = colorUrl(it.url, it.color_id);
    const iv = rawInterval(it, it.hot_reason != null, s);
    fastest.set(key, Math.min(fastest.get(key) ?? Infinity, iv));
  }
  let priorityLoad = 0, normalLoad = 0;
  for (const iv of fastest.values()) {
    if (iv <= s.priority) priorityLoad += 60 / iv;
    else normalLoad += 60 / iv;
  }
  const budget = MAX_REQUESTS_PER_MINUTE;
  if (priorityLoad + normalLoad <= budget) {
    s.stretch = { priority: 1, normal: 1 };
  } else if (priorityLoad < budget * 0.8) {
    // Keep priority items as they are; give normal items what is left.
    s.stretch = { priority: 1, normal: normalLoad / (budget - priorityLoad) };
  } else {
    const all = (priorityLoad + normalLoad) / budget;
    s.stretch = { priority: all, normal: all };
  }
  await db.from("app_settings").update({
    load_per_minute: Math.round((priorityLoad + normalLoad) * 10) / 10,
    load_stretch: Math.round(s.stretch.normal * 100) / 100,
  }).eq("id", 1);
}

/** 403/429 or a bot-protection page means the brand is blocking us. */
function isBlocked(e: unknown): boolean {
  return e instanceof BrandError && (e.status === 403 || e.status === 429);
}

async function syncWatchlists(db: Db): Promise<number> {
  const due = iso(new Date(Date.now() - WATCHLIST_SYNC_MINUTES * 60_000));
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
        .update({ name: wishlist.name, last_synced_at: iso(), last_error: null }).eq("id", list.id);
      synced++;
    } catch (e) {
      await db.from("watchlists").update({ last_synced_at: iso(), last_error: errorText(e) }).eq("id", list.id);
    }
  });
  return synced;
}

/** Last sell-out and the hours of day each item came into stock (last 60 days). */
async function loadHistory(db: Db, itemIds: string[]): Promise<Map<string, History>> {
  const history = new Map<string, History>();
  if (!itemIds.length) return history;
  const { data } = await db.from("stock_events")
    .select("item_id, started_at, ended_at")
    .eq("kind", "in_stock")
    .in("item_id", itemIds)
    .gt("started_at", iso(new Date(Date.now() - 60 * 86_400_000)));
  for (const e of data ?? []) {
    const h = history.get(e.item_id) ?? { lastSoldOut: null, restockHours: new Set<number>() };
    h.restockHours.add(istanbulHour(new Date(e.started_at)));
    if (e.ended_at && (!h.lastSoldOut || new Date(e.ended_at) > h.lastSoldOut)) h.lastSoldOut = new Date(e.ended_at);
    history.set(e.item_id, h);
  }
  return history;
}

async function checkDueItems(db: Db, settings: Settings): Promise<Stats> {
  const [{ data: items, error }, { data: profiles }] = await Promise.all([
    db.from("tracked_items")
      .select("id, user_id, brand, url, color_id, wanted_sizes, sizes, price, last_ok_at, tier_id, auto_priority")
      .eq("active", true)
      .or(`next_check_at.is.null,next_check_at.lte.${iso(new Date(Date.now() + 2000))}`),
    db.from("profiles").select("user_id, ntfy_topic"),
  ]);
  if (error) throw error;
  const topics = new Map((profiles ?? []).map((p) => [p.user_id, p.ntfy_topic as string | null]));
  const due = (items ?? []) as Item[];
  const history = await loadHistory(db, due.map((i) => i.id));

  // Fetch each product colour once, even if several items/users track it. The
  // colour goes in ?v1= because Zara names the product after the requested colour.
  const groups = new Map<string, Item[]>();
  for (const it of due) {
    const key = colorUrl(it.url, it.color_id);
    groups.set(key, [...(groups.get(key) ?? []), it]);
  }

  const stats: Stats = { checked: 0, failed: 0, cameIn: 0, hot: 0, blocked: null };
  await mapLimit([...groups.entries()], CONCURRENCY, async ([url, rows]) => {
    let product: ProductInfo;
    try {
      const { adapter, url: parsed } = resolveAdapter(url);
      product = await adapter.fetchProduct(parsed);
    } catch (e) {
      stats.failed += rows.length;
      if (isBlocked(e)) stats.blocked = errorText(e);
      // Retry failing items at the normal rate, not the fast one, to avoid hammering a block.
      await db.from("tracked_items").update({
        last_checked_at: iso(),
        last_error: errorText(e),
        next_check_at: iso(new Date(Date.now() + Math.max(settings.normal, 60) * 1000)),
      }).in("id", rows.map((r) => r.id));
      return;
    }
    await Promise.all(rows.map((item) =>
      applyResult(db, item, product, topics.get(item.user_id) ?? null, history.get(item.id), settings, stats)
    ));
  });
  return stats;
}

async function applyResult(
  db: Db,
  item: Item,
  product: ProductInfo,
  topic: string | null,
  history: History | undefined,
  settings: Settings,
  stats: Stats,
) {
  const now = new Date();
  const color = pickColor(product, item.color_id);
  const sizes: StoredSize[] = (color?.sizes ?? []).map((s) => ({ name: s.name, availability: s.availability }));
  const price = color?.price ?? null;
  const { cameIn, wentOut, comingSoon } = diffSizes(item, sizes);

  const lastSoldOut = wentOut.length ? now : history?.lastSoldOut ?? null;
  const hot = hotReason(wantedComingSoon(item.wanted_sizes, sizes), lastSoldOut, history?.restockHours ?? new Set(), now);
  if (hot) stats.hot++;

  await db.from("tracked_items").update({
    external_id: product.externalId,
    name: product.name,
    color_id: color?.id ?? item.color_id,
    color_name: color?.name ?? null,
    image_url: color?.imageUrl ?? null,
    price,
    currency: product.currency,
    sizes,
    last_checked_at: iso(now),
    last_ok_at: iso(now),
    last_error: null,
    hot_reason: hot,
    next_check_at: iso(new Date(now.getTime() + intervalFor(item, hot !== null, settings) * 1000)),
  }).eq("id", item.id);
  stats.checked++;

  if (wentOut.length) {
    await db.from("stock_events").update({ ended_at: iso(now) })
      .eq("item_id", item.id).eq("kind", "in_stock").is("ended_at", null).in("size_name", wentOut);
  }

  const link = colorUrl(product.url, color?.id ?? null);
  const base = {
    user_id: item.user_id,
    item_id: item.id,
    brand: product.brand,
    product_name: product.name,
    color_name: color?.name ?? null,
    image_url: color?.imageUrl ?? null,
    url: link,
    price,
  };
  const head = `${brandName(product.brand)}: ${product.name}`;
  const colorPart = color ? ` · ${color.name}` : "";
  const events: { kind: string; sizes: string[]; old_price?: number | null; note: Notification | null }[] = [];

  if (cameIn.length) {
    stats.cameIn += cameIn.length;
    const low = sizes.filter((s) => cameIn.includes(s.name) && s.availability === "low_on_stock").length > 0;
    events.push({
      kind: "in_stock",
      sizes: cameIn,
      note: {
        topic: "",
        title: `🟢 ${cameIn.join(", ")} stokta! ${head}`,
        message: `${money(price, product.currency)}${colorPart}${low ? " · Az kaldı, hızlı ol!" : ""}`,
        priority: 5,
        tags: ["shopping_bags"],
      },
    });
  }
  if (comingSoon.length) {
    events.push({
      kind: "coming_soon",
      sizes: comingSoon,
      note: {
        topic: "",
        title: `⏳ Hazır ol: ${comingSoon.join(", ")} yakında geliyor`,
        message: `${head}${colorPart}. Bu ürün artık daha sık kontrol ediliyor.`,
        priority: 4,
        tags: ["hourglass"],
      },
    });
  }
  if (item.price != null && price != null && price < item.price) {
    events.push({
      kind: "price_drop",
      sizes: [""],
      old_price: item.price,
      note: {
        topic: "",
        title: `🏷️ Fiyat düştü: ${head}`,
        message: `${money(item.price, product.currency)} → ${money(price, product.currency)}${colorPart}`,
        priority: 4,
        tags: ["label"],
      },
    });
  }

  for (const ev of events) {
    let notified = false;
    if (topic && ev.note) {
      try {
        await sendNtfy({ ...ev.note, topic, click: link, imageUrl: color?.imageUrl });
        notified = true;
      } catch (e) {
        console.error("ntfy failed", item.id, errorText(e));
      }
    }
    await db.from("stock_events").insert(ev.sizes.map((size) => ({
      ...base,
      kind: ev.kind,
      size_name: size,
      old_price: ev.old_price ?? null,
      notified,
    })));
  }
}

/** Warn every user (at most hourly) when some items could not be read for a while. */
async function alertIfFailing(db: Db, settings: Settings) {
  if (settings.lastHealthAlert && Date.now() - settings.lastHealthAlert.getTime() < 3_600_000) return;
  const cutoff = iso(new Date(Date.now() - FAILING_ALERT_MINUTES * 60_000));
  const { data: failing } = await db.from("tracked_items")
    .select("name, last_error")
    .eq("active", true)
    .not("last_error", "is", null)
    .or(`last_ok_at.is.null,last_ok_at.lt.${cutoff}`)
    .limit(20);
  if (!failing?.length) return;

  await db.from("app_settings").update({ last_health_alert_at: iso() }).eq("id", 1);
  const { data: profiles } = await db.from("profiles").select("ntfy_topic");
  const sample = failing.slice(0, 3).map((f) => f.name ?? "ürün").join(", ");
  await Promise.all((profiles ?? []).filter((p) => p.ntfy_topic).map((p) =>
    sendNtfy({
      topic: p.ntfy_topic!,
      title: "⚠️ Stok Takip: bazı ürünler kontrol edilemiyor",
      message: `${failing.length} ürün ${FAILING_ALERT_MINUTES} dakikadır okunamıyor (${sample}). Hata: ${
        failing[0].last_error
      }`,
      priority: 4,
      tags: ["warning"],
    }).catch((e) => console.error("ntfy failed", errorText(e)))
  ));
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) return json({ error: "unauthorized" }, 401);

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const started = new Date();
  let result: Stats & { synced: number } | null = null;
  let error: string | null = null;
  try {
    const settings = await loadSettings(db);
    if (settings.backoffUntil && settings.backoffUntil > started) {
      return json({ skipped: "backoff", until: iso(settings.backoffUntil) });
    }
    const synced = await syncWatchlists(db);
    await planLoad(db, settings);
    result = { synced, ...(await checkDueItems(db, settings)) };
    if (result.blocked) {
      // Stop everything for a while; hammering a block can turn it into a long ban.
      await db.from("app_settings").update({
        backoff_until: iso(new Date(Date.now() + BACKOFF_MINUTES * 60_000)),
        backoff_reason: result.blocked,
      }).eq("id", 1);
      error = `Engellendi, kontroller ${BACKOFF_MINUTES} dk durduruldu: ${result.blocked}`;
    }
    await alertIfFailing(db, settings);
  } catch (e) {
    error = errorText(e);
    console.error(error);
  }
  const ms = Date.now() - started.getTime();
  // Only runs that did something are logged; idle wake-ups would flood the log.
  if (error || (result && (result.synced || result.checked || result.failed))) {
    await Promise.all([
      db.from("check_runs").insert({
        started_at: iso(started),
        duration_ms: ms,
        lists_synced: result?.synced ?? 0,
        items_checked: result?.checked ?? 0,
        items_failed: result?.failed ?? 0,
        came_in: result?.cameIn ?? 0,
        error,
      }),
      db.from("check_runs").delete().lt("started_at", iso(new Date(Date.now() - 86_400_000))),
    ]);
  }
  return error ? json({ error, ms }, 500) : json({ ...result, ms });
});
