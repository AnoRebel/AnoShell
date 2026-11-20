import { useStorage } from "nitropack/runtime";
import { useRuntimeConfig } from "nuxt/server";

/**
 * The installer scripts (anod/installer/*.sh, bundled as server assets) as this
 * site serves them: `curl -fsSL <site>/i | bash`. The stable site (main) hands
 * out the stable channel, the dev site the dev one: the script's
 * `ANO_SITE_CHANNEL=` line is set to match.
 */
export async function serveInstaller(name: "install.sh" | "uninstall.sh"): Promise<Response> {
  const raw = await useStorage("assets:installer").getItemRaw(name);
  if (!raw) return new Response(`# ${name} is missing from this site\nexit 1\n`, { status: 404 });
  const channel = useRuntimeConfig().public.docs?.version === "dev" ? "dev" : "stable";
  const text = Buffer.from(raw as Uint8Array).toString("utf8").replace(/^ANO_SITE_CHANNEL=.*$/m, `ANO_SITE_CHANNEL=${channel}`);
  return new Response(text, {
    headers: {
      "content-type": "text/x-shellscript; charset=utf-8",
      // Short: a release reaches curl users within minutes.
      "cache-control": "public, max-age=300",
      "x-content-type-options": "nosniff",
    },
  });
}
