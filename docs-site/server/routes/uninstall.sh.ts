import { defineEventHandler } from "nuxt/server";

import { serveInstaller } from "../lib/installer";

// curl -fsSL <this site>/uninstall.sh | bash
export default defineEventHandler(() => serveInstaller("uninstall.sh"));
