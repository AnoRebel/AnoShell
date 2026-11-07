<script setup lang="ts">
/*
 * Replaces the layer's page. Two differences:
 * - Previous/next follow app.config's catalogue (the sidebar's order) and show
 *   its descriptions; the layer's follow file names, so they jumped around.
 * - The page's own "# Title" isn't drawn again under the header (the pages
 *   keep it for GitHub), and the header shows no description, because the
 *   description is the first paragraph, which the body already starts with.
 */
import { kebabCase } from "scule";
import type { ContentNavigationItem } from "@nuxt/content";
import { findPageHeadline } from "@nuxt/content/utils";

definePageMeta({ layout: "docs" });

const route = useRoute();
const { isOpen } = useAssistant();
const appConfig = useAppConfig();
const navigation = inject<Ref<ContentNavigationItem[]>>("navigation");
const { anoshell } = appConfig as unknown as {
  anoshell: { pages: { slug: string; title: string; description: string }[] };
};

const { data: page } = await useAsyncData(kebabCase(route.path), () =>
  queryCollection("docs").path(route.path).first(),
);

if (!page.value) {
  throw createError({ statusCode: 404, statusMessage: "Page not found", fatal: true });
}

const title = page.value.seo?.title || page.value.title;
const description = page.value.seo?.description || page.value.description;

const headline = ref(findPageHeadline(navigation?.value, page.value.path));
const breadcrumbs = computed(() => findPageBreadcrumbs(navigation?.value, page.value?.path || ""));
useSeo({ title, description, type: "article", breadcrumbs });
watch(
  () => navigation?.value,
  () => {
    headline.value = findPageHeadline(navigation?.value, page.value?.path) || headline.value;
  },
);

// The body without its leading "# Title".
const body = computed(() => {
  const value = page.value!.body as unknown as { value?: unknown[] };
  const nodes = value?.value;
  if (!Array.isArray(nodes) || !Array.isArray(nodes[0]) || nodes[0][0] !== "h1") return page.value!;
  return { ...page.value!, body: { ...value, value: nodes.slice(1) } };
});

const surround = computed(() => {
  const at = anoshell.pages.findIndex((entry) => `/${entry.slug}` === route.path);
  const link = (entry?: { slug: string; title: string; description: string }) =>
    entry ? { title: entry.title, description: entry.description, path: `/${entry.slug}` } : undefined;
  return at < 0 ? [] : [link(anoshell.pages[at - 1]), link(anoshell.pages[at + 1])];
});
</script>

<template>
  <UPage v-if="page" :ui="isOpen ? { center: 'lg:col-span-10' } : undefined">
    <UPageHeader
      :title="page.title"
      :headline="headline"
      :ui="{ wrapper: 'flex-row items-center flex-wrap justify-between' }"
    >
      <template #links>
        <LazyDocsPageHeaderLinks hydrate-on-idle />
      </template>
    </UPageHeader>

    <UPageBody>
      <ContentRenderer :value="body" />
      <UContentSurround :surround="surround" />
    </UPageBody>

    <template v-if="!isOpen" #right>
      <DocsAsideRight :page="page" />
    </template>
  </UPage>
</template>
