<script setup lang="ts">
const { docs, current, switchTo } = useDocsVersions();

const items = computed(() =>
  docs.versions.map((entry) => ({
    label: entry.label,
    suffix: entry.version,
    icon: entry.version === current.value.version ? "i-lucide-check" : undefined,
    disabled: entry.version === current.value.version,
    onSelect: () => switchTo(entry),
  })),
);
</script>

<template>
  <UDropdownMenu :items="items" :content="{ align: 'start' }">
    <UButton
      :label="current.version"
      trailing-icon="i-lucide-chevron-down"
      color="neutral"
      variant="subtle"
      size="xs"
      class="font-mono"
      :aria-label="`Documentation version: ${current.label}. Choose another version`"
    />
  </UDropdownMenu>
</template>
