<!-- Replaces the layer's: the name, and beside it the version being read. -->
<template>
  <div class="flex items-center gap-3">
    <NuxtLink to="/" aria-label="AnoShell documentation" class="flex items-center gap-2">
      <span class="font-semibold">AnoShell</span>
      <span class="text-muted hidden sm:inline">docs</span>
    </NuxtLink>
    <VersionSwitcher />
  </div>
</template>
