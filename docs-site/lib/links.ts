/**
 * Links inside the pages are written for GitHub: `anod.md`, `../anod/install.sh`.
 * On the site a page is `/anod`, docs/images/ is served at /images, and any
 * other file lives on GitHub at the branch this version was built from.
 * Rewritten once, at build time.
 */
import { posix } from "node:path";

export const REPOSITORY = "AnoRebel/AnoShell";

export function rewriteLink(url: string, branch: string): string {
  if (/^([a-z][a-z0-9+.-]*:|#|\/)/i.test(url)) return url; // absolute, anchor, or site path
  const [path = "", hash = ""] = url.split(/(?=#)/);
  const page = /^(?:\.\/)?([\w-]+)\.md$/.exec(path);
  if (page) return `/${page[1]}${hash}`;
  const asset = /^(?:\.\/)?(images\/[\w.-]+)$/.exec(path); // served by the site (nitro publicAssets)
  if (asset) return `/${asset[1]}${hash}`;
  const file = posix.normalize(posix.join("docs", path));
  return `https://github.com/${REPOSITORY}/blob/${branch}/${file}${hash}`;
}

interface Node {
  type: string;
  url?: string;
  children?: Node[];
  data?: Record<string, unknown>;
}

/*
 * A link to a clip in images/ plays inline on the site, in a Video.js player
 * (app/components/content/DocVideo.vue). As a link
 * the router took /images/x.webm for a page and showed its 404; GitHub keeps
 * the link.
 */
function videoOf(node: Node): Node | undefined {
  if (node.type !== "link" || !/^\/images\/[\w.-]+\.(webm|mp4)$/.test(node.url ?? "")) return;
  const label = node.children?.map((child) => (child as { value?: string }).value ?? "").join("") ?? "";
  return { type: "video", data: { hName: "doc-video", hProperties: { src: node.url, label } }, children: [] };
}

function walk(node: Node, branch: string) {
  if ((node.type === "link" || node.type === "definition") && node.url)
    node.url = rewriteLink(node.url, branch);
  node.children = node.children?.map((child) => {
    walk(child, branch);
    return videoOf(child) ?? child;
  });
}

/** Remark plugin: `{ branch }` names the branch links into the repository point at. */
export default function remarkDocLinks(options: { branch?: string } = {}) {
  return (tree: Node) => walk(tree, options.branch || "main");
}
