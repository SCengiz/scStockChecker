import { type BrandAdapter, BrandError } from "./types.ts";
import { zara } from "./zara.ts";

export * from "./types.ts";

export const adapters: BrandAdapter[] = [zara];

export type LinkKind = "product" | "wishlist";

export function resolveAdapter(raw: string): { adapter: BrandAdapter; kind: LinkKind; url: URL } {
  let url: URL;
  try {
    url = new URL(raw.trim());
  } catch {
    throw new BrandError("Geçersiz link", 400);
  }
  for (const adapter of adapters) {
    if (adapter.matchesProduct(url)) return { adapter, kind: "product", url };
    if (adapter.matchesWishlist(url)) return { adapter, kind: "wishlist", url };
  }
  throw new BrandError(`Bu marka henüz desteklenmiyor (${url.hostname}). Şimdilik sadece Zara linkleri takip edilebilir.`, 400);
}
