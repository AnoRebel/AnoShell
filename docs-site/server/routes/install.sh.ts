import { defineEventHandler } from "nuxt/server";

import { serveInstaller } from "../lib/installer";

// curl -fsSL <this site>/install.sh | bash
export default defineEventHandler(() => serveInstaller("install.sh"));
