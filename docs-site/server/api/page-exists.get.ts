import { queryCollection } from "@nuxt/content/server";
import { defineEventHandler, getQuery, handleCors } from "nuxt/server";

/**
 * Whether this version has a page, asked by the other version's switcher
 * before it sends somebody here. A yes/no about public pages, so any origin
 * may ask (the versions list is runtime config, so origins aren't fixed).
 */
export default defineEventHandler(async (event) => {
  const preflight = handleCors(event, { origin: "*", methods: ["GET"] });
  if (preflight) return preflight;

  const path = String(getQuery(event).path ?? "");
  if (!/^\/[\w\-/]*$/.test(path)) return { exists: false };
  if (path === "/") return { exists: true };
  // ponytail: nuxt/server's RequestEvent vs Content's H3Event type; same object at runtime.
  const page = await queryCollection(event as never, "docs").path(path).select("path").first();
  return { exists: Boolean(page) };
});
