import { type Availability, isAvailable, type ProductInfo } from "./brands/index.ts";

export interface StoredSize {
  name: string;
  availability: Availability;
}

export interface ItemRow {
  id: string;
  user_id: string;
  url: string;
  color_id: string | null;
  name: string | null;
  wanted_sizes: string[];
  sizes: StoredSize[];
}

const norm = (s: string) => s.trim().toLowerCase();

/** True when the user wants this size (an empty list means any size). */
export function isWanted(wanted: string[], size: string): boolean {
  return wanted.length === 0 || wanted.some((w) => norm(w) === norm(size));
}

/**
 * Sizes the user wants that just became available.
 * Nothing is reported on the first check (no previous data), so adding an item
 * that is already in stock does not send a notification.
 */
export function newlyAvailable(item: Pick<ItemRow, "wanted_sizes" | "sizes">, next: StoredSize[]): string[] {
  if (item.sizes.length === 0) return [];
  const before = new Map(item.sizes.map((s) => [norm(s.name), s.availability]));
  return next
    .filter((s) => isWanted(item.wanted_sizes, s.name) && isAvailable(s.availability))
    .filter((s) => {
      const prev = before.get(norm(s.name));
      return prev === undefined || !isAvailable(prev);
    })
    .map((s) => s.name);
}

/** Pick the tracked colour of a product (falls back to the first colour). */
export function pickColor(product: ProductInfo, colorId: string | null) {
  return product.colors.find((c) => c.id === colorId) ?? product.colors[0] ?? null;
}
