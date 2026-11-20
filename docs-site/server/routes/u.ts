import { defineEventHandler } from "nuxt/server";

import { serveInstaller } from "../lib/installer";

// curl -fsSL <this site>/u | bash
export default defineEventHandler(() => serveInstaller("uninstall.sh"));
