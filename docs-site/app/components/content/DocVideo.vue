<script setup lang="ts">
/**
 * A clip from docs/images in a Video.js v10 player (lib/links.ts turns the
 * pages' clip links into this). The player elements register in the browser.
 */
defineProps<{ src: string; label?: string }>();

onMounted(async () => {
  await Promise.all([import("@videojs/html/video/player"), import("@videojs/html/video/skin")]);
});
</script>

<template>
  <video-player class="not-prose my-4 block">
    <video-skin class="doc-video">
      <video :src="src" :aria-label="label" muted loop playsinline preload="metadata" />
    </video-skin>
  </video-player>
</template>

<style scoped>
.doc-video {
  display: block;
  width: 100%;
  --media-accent-color: var(--ui-primary);
  --media-border-radius: var(--ui-radius, 0.5rem);
}
video-skin:not(:defined) {
  visibility: hidden;
}
</style>
