<script setup lang="ts">
// Edits go to the branch of the version being read.
const route = useRoute();
const { docs, current } = useDocsVersions();

const links = computed(() => [
  {
    label: `Edit on GitHub (${current.value.version})`,
    icon: "i-simple-icons-github",
    to: `https://github.com/${docs.repository}/edit/${current.value.version}/docs${route.path}.md`,
    target: "_blank",
  },
  {
    label: "Report a problem",
    icon: "i-lucide-circle-alert",
    to: `https://github.com/${docs.repository}/issues/new`,
    target: "_blank",
  },
]);
</script>

<template>
  <div class="space-y-6">
    <USeparator type="dashed" />
    <UPageLinks title="This page" :links="links" />
  </div>
</template>
