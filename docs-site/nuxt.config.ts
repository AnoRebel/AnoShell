import remarkDocLinks, { REPOSITORY } from "./lib/links";

/**
 * The AnoShell documentation site.
 *
 * One build per version: main and dev are each deployed from their own branch
 * with DOCS_VERSION naming it. The header's switcher moves between the
 * deployments; NUXT_PUBLIC_DOCS_VERSIONS (JSON) replaces the list at runtime.
 *
 * DOCS_VERSION is read at build time, because links from a page into the
 * repository are resolved then and point at that branch's files.
 */
const version = process.env.DOCS_VERSION || "dev";

const versions = [
  { version: "main", label: "Stable", url: "https://anoshell.anorebel.net" },
  { version: "dev", label: "Development", url: "https://dev.anoshell.anorebel.net" },
];

export default defineNuxtConfig({
  extends: ["docus"],

  compatibilityDate: "2026-10-01",

  site: {
    name: "AnoShell",
    url: versions.find((entry) => entry.version === version)?.url,
  },

  runtimeConfig: {
    public: {
      docs: { version, versions, repository: REPOSITORY },
    },
  },

  content: {
    build: {
      markdown: {
        remarkPlugins: {
          "anoshell-doc-links": { instance: remarkDocLinks, options: { branch: version } },
        },
      },
    },
  },

  // Icons named only in app.config strings aren't found by the scan; bundle them.
  icon: { clientBundle: { icons: ["lucide:book-open", "lucide:cpu", "lucide:files"] } },

  // Social images are drawn only while prerendering, which this site doesn't do.
  ogImage: { enabled: false },

  nitro: {
    /*
     * Rendered on request, not prerendered: a prerendered page would carry the
     * runtime config it was built with, and the versions list is given to the
     * container when it starts.
     */
    prerender: { crawlLinks: false, ignore: ["/"] },
  },
});
