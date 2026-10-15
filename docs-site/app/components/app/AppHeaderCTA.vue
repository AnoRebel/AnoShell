<script setup lang="ts">
// The repository, at the branch these docs were built from.
const { docs, current } = useDocsVersions();
</script>

<template>
  <UButton
    icon="i-simple-icons-github"
    :to="`https://github.com/${docs.repository}/tree/${current.version}`"
    target="_blank"
    color="neutral"
    variant="ghost"
    aria-label="Source on GitHub"
  />
</template>
