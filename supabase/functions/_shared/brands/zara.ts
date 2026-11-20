import { getJson } from "./http.ts";
import {
  type Availability,
  type BrandAdapter,
  BrandError,
  type ColorInfo,
  type ProductInfo,
  type WishlistInfo,
} from "./types.ts";

// Product pages look like https://www.zara.com/tr/tr/suni-kurk-ceket-p04968232.html?v1=567275536
const PRODUCT_PATH = /^\/([a-z]{2})\/([a-z]{2})\/(.+)-p(\d{8})\.html$/;

function isZaraHost(url: URL): boolean {
  return url.hostname === "www.zara.com" || url.hostname === "zara.com";
}

function normalizeAvailability(raw: unknown): Availability {
  switch (raw) {
    case "in_stock":
    case "low_on_stock":
    case "out_of_stock":
    case "coming_soon":
      return raw;
    case "back_soon":
      return "coming_soon";
    default:
      return "unknown";
  }
}

// deno-lint-ignore no-explicit-any
type Json = any;

function imageOf(color: Json): string | null {
  const media = (color.xmedia ?? []).find((m: Json) => m?.type === "image") ?? color.xmedia?.[0];
  return media?.extraInfo?.deliveryUrl ?? null;
}

export function parseZaraProduct(json: Json, pageUrl: URL): ProductInfo {
  const product = json?.product;
  if (!product?.detail?.colors) throw new BrandError("Zara response has no product data");
  const m = pageUrl.pathname.match(PRODUCT_PATH);
  const canonical = m ? `${pageUrl.origin}${pageUrl.pathname}` : pageUrl.toString();

  const colors: ColorInfo[] = product.detail.colors.map((c: Json) => ({
    // productId is the color-specific id Zara uses in the ?v1= query parameter.
    id: String(c.productId ?? c.id),
    name: String(c.name ?? c.id ?? ""),
    imageUrl: imageOf(c),
    price: typeof c.price === "number" ? c.price / 100 : null,
    sizes: (c.sizes ?? []).map((s: Json) => ({
      id: String(s.sku ?? s.id),
      name: String(s.name ?? ""),
      availability: normalizeAvailability(s.availability),
    })),
  }));

  return {
    brand: "zara",
    externalId: String(product.id),
    name: String(product.name ?? ""),
    url: canonical,
    currency: json?.docInfo?.currency ?? (m?.[1] === "tr" ? "TRY" : null),
    colors,
  };
}

export const zara: BrandAdapter = {
  brand: "zara",

  matchesProduct(url) {
    return isZaraHost(url) && PRODUCT_PATH.test(url.pathname);
  },

  matchesWishlist(url) {
    return isZaraHost(url) && WISHLIST_PATH.test(url.pathname);
  },

  async fetchProduct(url) {
    const m = url.pathname.match(PRODUCT_PATH);
    if (!m) throw new BrandError("Not a Zara product URL");
    const api = new URL(`${url.origin}${url.pathname}`);
    api.searchParams.set("ajax", "true");
    const v1 = url.searchParams.get("v1");
    if (v1) api.searchParams.set("v1", v1);
    const json = await getJson(api.toString(), `${m[2]}-${m[1].toUpperCase()},${m[2]};q=0.9`);
    return parseZaraProduct(json, url);
  },

  async fetchWishlist(url) {
    const m = url.pathname.match(WISHLIST_PATH);
    if (!m) throw new BrandError("Not a Zara wishlist URL");
    // The app shares https://www.zara.com/share/wishlist/<token>?locale=tr_TR, which
    // redirects to /<country>/<lang>/user/share/wishlist/<token>.
    const [lang, country] = (url.searchParams.get("locale") ?? "tr_TR").toLowerCase().split("_");
    const cc = m[1] ?? country ?? "tr";
    const lc = m[2] ?? lang ?? "tr";
    const api = `https://www.zara.com/${cc}/${lc}/user/share/wishlist/${m[3]}?ajax=true`;
    const json = await getJson(api, `${lc}-${cc.toUpperCase()},${lc};q=0.9`);
    return parseZaraWishlist(json, cc, lc);
  },
};

// https://www.zara.com/share/wishlist/<token> or /tr/tr/user/share/wishlist/<token>
const WISHLIST_PATH = /^(?:\/([a-z]{2})\/([a-z]{2})\/user)?\/share\/wishlist\/([A-Za-z0-9_-]+)\/?$/;

export function parseZaraWishlist(json: Json, cc: string, lang: string): WishlistInfo {
  const wishlist = json?.wishlist;
  if (!wishlist || !Array.isArray(wishlist.items)) throw new BrandError("Zara response has no wishlist data");
  const items: WishlistInfo["items"] = [];
  for (const it of wishlist.items) {
    const p = it?.unprocessedProduct;
    const keyword = p?.seo?.keyword;
    const seoId = p?.seo?.seoProductId;
    if (!keyword || !seoId) continue;
    // The list stores one colour per entry; its productId is the ?v1= colour id.
    const colorId = it?.product?.productId ?? p?.seo?.discernProductId ?? null;
    items.push({
      url: `https://www.zara.com/${cc}/${lang}/${keyword}-p${seoId}.html`,
      colorId: colorId == null ? null : String(colorId),
    });
  }
  return { brand: "zara", name: wishlist.name ?? null, items };
}
