export interface DocsVersion {
  /** The branch this version is built from. */
  version: string;
  label: string;
  url: string;
}

/** The version being read, the others, and how to move between them. */
export function useDocsVersions() {
  const docs = useRuntimeConfig().public.docs as unknown as {
    version: string;
    versions: DocsVersion[];
    repository: string;
  };
  const route = useRoute();

  const current = computed(
    () =>
      docs.versions.find((entry) => entry.version === docs.version) ?? {
        version: docs.version,
        label: docs.version,
        url: "",
      },
  );
  const stable = computed(() => docs.versions.find((entry) => entry.version === "main"));

  /** Opens the other version at this page if it has it, at its front page otherwise. */
  async function switchTo(target: DocsVersion) {
    let destination = target.url;
    try {
      const { exists } = await $fetch<{ exists: boolean }>("/api/page-exists", {
        baseURL: target.url,
        query: { path: route.path },
        timeout: 3000,
      });
      if (exists) destination = target.url + route.path + route.hash;
    } catch {
      // Unreachable or older than this check: its front page is still right.
    }
    window.location.assign(destination);
  }

  return { docs, current, stable, switchTo };
}
