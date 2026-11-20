import { BrandError } from "./types.ts";

const USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15";

/** GET a URL that should return JSON, the way the brand's own website requests it. */
export async function getJson(url: string, acceptLanguage = "tr-TR,tr;q=0.9"): Promise<unknown> {
  const res = await fetch(url, {
    headers: {
      "User-Agent": USER_AGENT,
      "Accept": "application/json, text/plain, */*",
      "Accept-Language": acceptLanguage,
    },
    redirect: "follow",
  });
  const type = res.headers.get("content-type") ?? "";
  if (!res.ok) {
    await res.body?.cancel();
    throw new BrandError(`HTTP ${res.status} for ${url}`, res.status);
  }
  if (!type.includes("json")) {
    // Usually a bot-protection interstitial page instead of data.
    await res.body?.cancel();
    throw new BrandError(`Expected JSON but got "${type}" for ${url} (blocked by bot protection?)`, 403);
  }
  return await res.json();
}
