export interface Notification {
  topic: string;
  title: string;
  message: string;
  click?: string;
  imageUrl?: string | null;
}

const NTFY_SERVER = Deno.env.get("NTFY_SERVER") ?? "https://ntfy.sh";

/** Publish a push notification to an ntfy topic (JSON publishing keeps Turkish characters intact). */
export async function sendNtfy(n: Notification): Promise<void> {
  const res = await fetch(NTFY_SERVER, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      topic: n.topic,
      title: n.title,
      message: n.message,
      click: n.click,
      attach: n.imageUrl ?? undefined,
      tags: ["shopping_bags"],
      priority: 4,
    }),
  });
  if (!res.ok) throw new Error(`ntfy ${res.status}: ${await res.text()}`);
  await res.body?.cancel();
}
