import { expect, test } from "bun:test";

import remarkDocLinks, { rewriteLink } from "./links";

test("page links become site paths, other files go to GitHub at the branch", () => {
  expect(rewriteLink("anod.md", "dev")).toBe("/anod");
  expect(rewriteLink("./architecture.md#blur", "main")).toBe("/architecture#blur");
  expect(rewriteLink("../anod/install.sh", "dev")).toBe(
    "https://github.com/AnoRebel/AnoShell/blob/dev/anod/install.sh",
  );
  expect(rewriteLink("https://example.com/a.md", "main")).toBe("https://example.com/a.md");
  expect(rewriteLink("#install", "main")).toBe("#install");
  expect(rewriteLink("images/scratchpad-grow.webm", "dev")).toBe("/images/scratchpad-grow.webm");
  expect(rewriteLink("images/../x.sh", "dev")).toBe("https://github.com/AnoRebel/AnoShell/blob/dev/docs/x.sh");
});

test("a clip link becomes the Video.js clip component; other links stay", () => {
  const tree = {
    type: "root",
    children: [{ type: "paragraph", children: [
      { type: "link", url: "images/scratchpad-grow.webm", children: [{ type: "text", value: "Watch it" }] },
      { type: "link", url: "anod.md", children: [] },
    ] }],
  };
  remarkDocLinks({ branch: "dev" })(tree as never);
  const [player, page] = (tree.children[0] as { children: any[] }).children;
  expect(player.data.hName).toBe("doc-video");
  expect(player.data.hProperties).toEqual({ src: "/images/scratchpad-grow.webm", label: "Watch it" });
  expect(page.url).toBe("/anod");
});
