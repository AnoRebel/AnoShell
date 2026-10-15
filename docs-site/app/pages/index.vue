<script setup lang="ts">
// The front page: every page in docs/, grouped as the sidebar groups them.
const appConfig = useAppConfig();
const { anoshell } = appConfig as unknown as {
  anoshell: {
    groups: { id: string; title: string; icon: string }[];
    pages: { slug: string; group: string; title: string; description: string }[];
  };
};
const { current } = useDocsVersions();

useSeoMeta({ title: "AnoShell documentation", description: appConfig.seo.description });

const groups = anoshell.groups
  .map((group) => ({ ...group, pages: anoshell.pages.filter((page) => page.group === group.id) }))
  .filter((group) => group.pages.length);
</script>

<template>
  <UMain>
    <UPageHero
      title="AnoShell"
      description="A Quickshell desktop shell for Hyprland and niri: bars, sidebars, a dock and a media pill that can fuse into one connected frame, with a companion daemon and CLI."
      :links="[
        { label: 'Get started', to: '/overview', icon: 'i-lucide-arrow-right', trailing: true },
        { label: 'Install', to: '/installation', color: 'neutral', variant: 'subtle' },
      ]"
    >
      <template #headline>
        <UBadge variant="subtle" color="neutral" class="font-mono"
          >{{ current.label }} · {{ current.version }}</UBadge
        >
      </template>
    </UPageHero>

    <UContainer class="pb-24 space-y-14">
      <section v-for="group in groups" :key="group.id" :aria-labelledby="`group-${group.id}`">
        <div class="mb-5 flex items-center gap-3">
          <UIcon :name="group.icon" class="size-5 text-primary shrink-0" />
          <h2 :id="`group-${group.id}`" class="text-xl font-semibold text-highlighted">
            {{ group.title }}
          </h2>
        </div>
        <UPageGrid>
          <UPageCard
            v-for="page in group.pages"
            :key="page.slug"
            :title="page.title"
            :description="page.description"
            :to="`/${page.slug}`"
            variant="subtle"
          />
        </UPageGrid>
      </section>
    </UContainer>
  </UMain>
</template>
