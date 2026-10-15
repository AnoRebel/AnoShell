<script setup lang="ts">
const { current, stable, switchTo } = useDocsVersions();
const show = computed(() => stable.value && current.value.version !== stable.value.version);
</script>

<template>
  <div
    v-if="show && stable"
    class="bg-primary/10 text-sm border-b border-default px-4 py-2 text-center text-pretty"
  >
    You're reading the development docs: they describe work that may not be released yet.
    <a
      :href="stable.url"
      class="font-medium text-highlighted underline underline-offset-2"
      @click.prevent="switchTo(stable)"
      >Read the stable docs</a
    >
  </div>
</template>
