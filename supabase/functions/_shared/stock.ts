import { type Availability, isAvailable, type ProductInfo } from "./brands/index.ts";

export interface StoredSize {
  name: string;
  availability: Availability;
}

export interface ItemRow {
  id: string;
  user_id: string;
  brand: string;
  url: string;
  color_id: string | null;
  wanted_sizes: string[];
  sizes: StoredSize[];
}

const norm = (s: string) => s.trim().toLocaleLowerCase("tr");
/** "M (US M)" -> "m": lets a typed "M" match Zara's longer size labels. */
const base = (s: string) => norm(s.replace(/\s*\(.*\)\s*$/, ""));

/** True when the user wants this size (an empty list means any size). */
export function isWanted(wanted: string[], size: string): boolean {
  return wanted.length === 0 || wanted.some((w) => norm(w) === norm(size) || base(w) === base(size));
}

function availableWanted(wanted: string[], sizes: StoredSize[]): Set<string> {
  return new Set(sizes.filter((s) => isAvailable(s.availability) && isWanted(wanted, s.name)).map((s) => s.name));
}

/**
 * Wanted sizes that came into stock / sold out / were announced as "coming
 * soon" since the previous check. Nothing is reported on the first check (no
 * previous data), so adding an item that is already in stock does not notify.
 */
export function diffSizes(
  item: Pick<ItemRow, "wanted_sizes" | "sizes">,
  next: StoredSize[],
): { cameIn: string[]; wentOut: string[]; comingSoon: string[] } {
  if (item.sizes.length === 0) return { cameIn: [], wentOut: [], comingSoon: [] };
  const before = availableWanted(item.wanted_sizes, item.sizes);
  const after = availableWanted(item.wanted_sizes, next);
  const prev = new Map(item.sizes.map((s) => [s.name, s.availability]));
  return {
    cameIn: [...after].filter((s) => !before.has(s)),
    wentOut: [...before].filter((s) => !after.has(s)),
    comingSoon: next
      .filter((s) => s.availability === "coming_soon" && isWanted(item.wanted_sizes, s.name))
      .filter((s) => prev.get(s.name) === "out_of_stock")
      .map((s) => s.name),
  };
}

/** Wanted sizes currently marked "coming soon". */
export function wantedComingSoon(wanted: string[], sizes: StoredSize[]): string[] {
  return sizes.filter((s) => s.availability === "coming_soon" && isWanted(wanted, s.name)).map((s) => s.name);
}

/** Hour of day (0-23) in Istanbul. */
export function istanbulHour(date: Date): number {
  return Number(new Intl.DateTimeFormat("en-GB", { hour: "2-digit", hour12: false, timeZone: "Europe/Istanbul" })
    .format(date)) % 24;
}

/**
 * Why an item should be checked at the fast rate right now, or null.
 * - a wanted size is "coming soon" (a restock is announced),
 * - a wanted size sold out within the last hour (it often comes back),
 * - it is the hour of day the item came into stock before.
 */
export function hotReason(
  comingSoon: string[],
  lastSoldOut: Date | null,
  restockHours: Set<number>,
  now: Date,
): string | null {
  if (comingSoon.length) return "coming_soon";
  if (lastSoldOut && now.getTime() - lastSoldOut.getTime() < 3_600_000) return "recently_sold_out";
  if (restockHours.has(istanbulHour(now))) return "restock_hour";
  return null;
}

/** Pick the tracked colour of a product (falls back to the first colour). */
export function pickColor(product: ProductInfo, colorId: string | null) {
  return product.colors.find((c) => c.id === colorId) ?? product.colors[0] ?? null;
}

/** Product page URL pinned to a colour (Zara's ?v1= parameter). */
export function colorUrl(url: string, colorId: string | null): string {
  if (!colorId) return url;
  const u = new URL(url);
  u.searchParams.set("v1", colorId);
  return u.toString();
}
