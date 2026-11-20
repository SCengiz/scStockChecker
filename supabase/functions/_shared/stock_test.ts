import { assertEquals } from "jsr:@std/assert@1";
import { isWanted, newlyAvailable } from "./stock.ts";

Deno.test("empty wanted list means any size", () => {
  assertEquals(isWanted([], "M"), true);
  assertEquals(isWanted(["m"], "M"), true);
  assertEquals(isWanted(["L"], "M"), false);
});

Deno.test("short size matches Zara's long label", () => {
  assertEquals(isWanted(["M"], "M (US M)"), true);
  assertEquals(isWanted(["m"], "M (US M)"), true);
  assertEquals(isWanted(["XL"], "L (US L)"), false);
  assertEquals(isWanted(["38"], "38"), true);
});

Deno.test("first check never notifies", () => {
  assertEquals(newlyAvailable({ wanted_sizes: ["M"], sizes: [] }, [{ name: "M", availability: "in_stock" }]), []);
});

Deno.test("notifies when a wanted size comes back", () => {
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
    { name: "L", availability: "in_stock" as const },
  ];
  assertEquals(newlyAvailable(item, next), ["M"]);
});

Deno.test("coming_soon does not count as in stock", () => {
  const item = { wanted_sizes: ["M"], sizes: [{ name: "M", availability: "out_of_stock" as const }] };
  assertEquals(newlyAvailable(item, [{ name: "M", availability: "coming_soon" }]), []);
});
