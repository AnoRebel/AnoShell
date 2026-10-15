import { fileURLToPath } from "node:url";

import { defineCollection, defineContentConfig, z } from "@nuxt/content";

/**
 * The pages are the repository's docs/ directory, which GitHub renders too.
 * There is no content/ here on purpose: a copy would drift. Replaces the
 * layer's own "docs" collection, which looks in content/.
 */
export default defineContentConfig({
  collections: {
    docs: defineCollection({
      type: "page",
      source: {
        cwd: fileURLToPath(new URL("../docs", import.meta.url)),
        include: "*.md",
        exclude: ["README.md"],
        prefix: "/",
      },
      // The layer's page template reads this; the pages never set it.
      schema: z.object({
        links: z
          .array(
            z.object({
              label: z.string(),
              icon: z.string(),
              to: z.string(),
              target: z.string().optional(),
            }),
          )
          .optional(),
      }),
    }),
  },
});
