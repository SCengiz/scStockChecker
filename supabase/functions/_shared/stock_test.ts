import { assertEquals } from "jsr:@std/assert@1";
import { colorUrl, diffSizes, hotReason, istanbulHour, isWanted } from "./stock.ts";

Deno.test("empty wanted list means any size", () => {
  assertEquals(isWanted([], "M"), true);
  assertEquals(isWanted(["m"], "M"), true);
  assertEquals(isWanted(["L"], "M"), false);
});

Deno.test("short size matches Zara's long label", () => {
  assertEquals(isWanted(["M"], "M (US M)"), true);
  assertEquals(isWanted(["XL"], "L (US L)"), false);
  assertEquals(isWanted(["38"], "38"), true);
});

Deno.test("first check reports nothing", () => {
  assertEquals(diffSizes({ wanted_sizes: ["M"], sizes: [] }, [{ name: "M", availability: "in_stock" }]), {
    cameIn: [],
    wentOut: [],
    comingSoon: [],
  });
});

Deno.test("reports wanted sizes announced as coming soon", () => {
  const item = {
    wanted_sizes: ["40"],
    sizes: [{ name: "40", availability: "out_of_stock" as const }, { name: "41", availability: "out_of_stock" as const }],
  };
  const next = [{ name: "40", availability: "coming_soon" as const }, { name: "41", availability: "coming_soon" as const }];
  assertEquals(diffSizes(item, next).comingSoon, ["40"]);
});

Deno.test("hot reasons", () => {
  const now = new Date("2026-11-21T06:30:00Z"); // 09:30 in Istanbul
  assertEquals(istanbulHour(now), 9);
  assertEquals(hotReason(["40"], null, new Set(), now), "coming_soon");
  assertEquals(hotReason([], new Date("2026-11-21T06:00:00Z"), new Set(), now), "recently_sold_out");
  assertEquals(hotReason([], new Date("2026-11-21T04:00:00Z"), new Set([9]), now), "restock_hour");
  assertEquals(hotReason([], null, new Set([10]), now), null);
});

Deno.test("reports wanted sizes coming in and selling out", () => {
  const item = {
    wanted_sizes: ["M", "L"],
    sizes: [
      { name: "S", availability: "out_of_stock" as const },
      { name: "M", availability: "out_of_stock" as const },
      { name: "L", availability: "in_stock" as const },
    ],
  };
  const next = [
    { name: "S", availability: "in_stock" as const },
    { name: "M", availability: "low_on_stock" as const },
    { name: "L", availability: "out_of_stock" as const },
  ];
  assertEquals(diffSizes(item, next), { cameIn: ["M"], wentOut: ["L"], comingSoon: [] });
});

Deno.test("coming_soon does not count as in stock", () => {
  const item = { wanted_sizes: ["M"], sizes: [{ name: "M", availability: "out_of_stock" as const }] };
  assertEquals(diffSizes(item, [{ name: "M", availability: "coming_soon" }]).cameIn, []);
});

Deno.test("colorUrl adds v1", () => {
  assertEquals(colorUrl("https://www.zara.com/tr/tr/x-p1.html", "9"), "https://www.zara.com/tr/tr/x-p1.html?v1=9");
  assertEquals(colorUrl("https://www.zara.com/tr/tr/x-p1.html", null), "https://www.zara.com/tr/tr/x-p1.html");
});
