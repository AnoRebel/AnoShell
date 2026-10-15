export default defineAppConfig({
  /*
   * Off: the layer builds "Edit this page" as <repo>/edit/<branch>/content/<file>,
   * and the pages are in docs/. DocsAsideRightBottom links the right file.
   */
  // @ts-expect-error the layer tests it for truthiness; its type only describes the object
  github: false,

  header: { title: "AnoShell" },

  seo: {
    title: "AnoShell documentation",
    description:
      "AnoShell: a Quickshell desktop shell for Hyprland and niri, with its companion daemon anod and the ano CLI.",
  },

  toc: { title: "On this page" },

  ui: {
    colors: { primary: "violet", neutral: "zinc" },
  },

  /** Sidebar order and the front page's cards. A page in docs/ not listed here lands under "More". */
  anoshell: {
    groups: [
      { id: "guide", title: "Guide", icon: "i-lucide-book-open" },
      { id: "internals", title: "Internals", icon: "i-lucide-cpu" },
    ],
    pages: [
      { slug: "overview", group: "guide", title: "Overview", description: "What AnoShell is: panel families, the connected frame and the pill." },
      { slug: "installation", group: "guide", title: "Installation", description: "Clone the shell, install anod and the ano CLI, pick a release channel." },
      { slug: "configuration", group: "guide", title: "Configuration", description: "Your config delta, the Settings pages, bar forms and groups." },
      { slug: "looks", group: "guide", title: "Looks and colours", description: "Liquid, Ink, Neo-tech, Clay; your own looks; colour modes." },
      { slug: "cli", group: "guide", title: "The ano CLI", description: "status, doctor, config, setup, backup and looks from a terminal." },
      { slug: "anod", group: "internals", title: "anod", description: "The companion daemon: supervision, event hooks, socket protocol." },
      { slug: "architecture", group: "internals", title: "Architecture", description: "How the shell is put together and the constraints that shaped it." },
    ],
  },
});
