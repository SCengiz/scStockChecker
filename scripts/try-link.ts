// Local check of a brand adapter: deno run --allow-net scripts/try-link.ts <url>
import { resolveAdapter } from "../supabase/functions/_shared/brands/index.ts";

const raw = Deno.args[0];
if (!raw) {
  console.error("usage: deno run --allow-net scripts/try-link.ts <url>");
  Deno.exit(1);
}
const { adapter, kind, url } = resolveAdapter(raw);
const result = kind === "product" ? await adapter.fetchProduct(url) : await adapter.fetchWishlist(url);
console.log(JSON.stringify(result, null, 2));
