// Called by the app (signed-in user) to read a pasted link before saving it:
// a product link returns its colours and sizes, a favourites link its products.
import { BrandError, resolveAdapter } from "../_shared/brands/index.ts";
import { corsHeaders, json } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  try {
    const { url } = await req.json();
    if (typeof url !== "string") return json({ error: "url is required" }, 400);
    const { adapter, kind, url: parsed } = resolveAdapter(url);
    if (kind === "product") {
      return json({ kind, product: await adapter.fetchProduct(parsed) });
    }
    return json({ kind, wishlist: await adapter.fetchWishlist(parsed) });
  } catch (e) {
    const status = e instanceof BrandError && e.status ? (e.status >= 500 ? 502 : e.status) : 500;
    return json({ error: e instanceof Error ? e.message : String(e) }, status);
  }
});
