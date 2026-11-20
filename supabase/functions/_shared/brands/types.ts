// Shared types for brand adapters.

export type Availability = "in_stock" | "low_on_stock" | "out_of_stock" | "coming_soon" | "unknown";

export interface SizeInfo {
  /** Stable id of the size within the color (brand specific, stored as text). */
  id: string;
  name: string;
  availability: Availability;
}

export interface ColorInfo {
  /** Stable id of the color variant (brand specific, stored as text). */
  id: string;
  name: string;
  imageUrl: string | null;
  /** Price in the store's currency, as a decimal number (e.g. 4290). */
  price: number | null;
  sizes: SizeInfo[];
}

export interface ProductInfo {
  brand: string;
  /** Brand's own product id. */
  externalId: string;
  name: string;
  /** Canonical product page URL (without color). */
  url: string;
  currency: string | null;
  colors: ColorInfo[];
}

export interface WishlistInfo {
  brand: string;
  name: string | null;
  /** Product page URLs found in the list, each optionally pinned to a color. */
  items: { url: string; colorId: string | null }[];
}

export interface BrandAdapter {
  brand: string;
  matchesProduct(url: URL): boolean;
  matchesWishlist(url: URL): boolean;
  fetchProduct(url: URL): Promise<ProductInfo>;
  fetchWishlist(url: URL): Promise<WishlistInfo>;
}

export function isAvailable(a: Availability): boolean {
  return a === "in_stock" || a === "low_on_stock";
}

export class BrandError extends Error {
  constructor(message: string, public readonly status?: number) {
    super(message);
  }
}
