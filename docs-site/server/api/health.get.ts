import { queryCollection } from "@nuxt/content/server";
import { defineEventHandler, setResponseStatus } from "nuxt/server";

/**
 * Health check for the deployment (Dokploy points at it, as does the image's
 * HEALTHCHECK): a real read of the content index, so a site that starts but
 * can't serve pages reports unhealthy (503).
 */
export default defineEventHandler(async (event) => {
  try {
    // ponytail: nuxt/server's RequestEvent vs Content's H3Event type; same object at runtime.
    const page = await queryCollection(event as never, "docs").path("/overview").select("path").first();
    if (!page) throw new Error("the overview page is missing");
    return { status: "healthy", version: process.env.DOCS_VERSION || "dev" };
  } catch (err) {
    setResponseStatus(event, 503);
    return { status: "unhealthy", error: err instanceof Error ? err.message : String(err) };
  }
});
