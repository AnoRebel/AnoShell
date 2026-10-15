import { expect, test } from "bun:test";

import { rewriteLink } from "./links";

test("page links become site paths, other files go to GitHub at the branch", () => {
  expect(rewriteLink("anod.md", "dev")).toBe("/anod");
  expect(rewriteLink("./architecture.md#blur", "main")).toBe("/architecture#blur");
  expect(rewriteLink("../anod/install.sh", "dev")).toBe(
    "https://github.com/AnoRebel/AnoShell/blob/dev/anod/install.sh",
  );
  expect(rewriteLink("https://example.com/a.md", "main")).toBe("https://example.com/a.md");
  expect(rewriteLink("#install", "main")).toBe("#install");
});
