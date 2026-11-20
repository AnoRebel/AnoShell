import { defineEventHandler } from "nuxt/server";

import { serveInstaller } from "../lib/installer";

// curl -fsSL <this site>/i | bash
export default defineEventHandler(() => serveInstaller("install.sh"));
