/**
 * Umami and Rybbit, when their site ids are set (Dokploy's environment, read
 * when the container starts, as in the portfolio and mapcn sites). Unset → no
 * script and nothing sent. Ids are checked, so nothing else reaches the page.
 */
const ID = /^[\w-]{1,64}$/;

export default defineNitroPlugin((nitro) => {
  const umami = process.env.NUXT_UMAMI_SITE_ID?.trim() ?? "";
  const rybbit = process.env.NUXT_RYBBIT_SITE_ID?.trim() ?? "";
  const tags: string[] = [];
  if (ID.test(umami))
    tags.push(`<script defer src="https://umami.anorebel.net/script.js" data-website-id="${umami}"></script>`);
  if (ID.test(rybbit))
    tags.push(`<script defer src="https://rybbit.anorebel.net/api/script.js" data-site-id="${rybbit}"></script>`);
  if (!tags.length) return;
  nitro.hooks.hook("render:html", (html) => {
    html.head.push(...tags);
  });
});
