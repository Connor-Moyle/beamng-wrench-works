<template>
  <div class="rh">
    <ModsMenu v-if="page === 'mod'" :mod="mod" :startTab="tab" :key="mod + '/' + tab" />
    <FindSetting v-else-if="page === 'find'" />
    <QuickSetup v-else />
  </div>
</template>

<script setup>
import { computed } from "vue"
import { useRoute } from "vue-router"
import ModsMenu from "./ModsMenu.vue"
import FindSetting from "./FindSetting.vue"
import QuickSetup from "./QuickSetup.vue"

// the Mods menu pages as a screen of their own (route menu.slrrMods): the pause menu cards show the same components. Also how the in-game check opens a page without a click:
// extensions.ui_router.navigate('menu.slrrMods', { page = 'mod', mod = 'car_surface_fx', tab = 'rain' })   (page: mod | find | quick)
const route = useRoute()
const page = computed(() => String(route.params.page || "quick"))
const mod = computed(() => String(route.params.mod || ""))
const tab = computed(() => String(route.params.tab || ""))
</script>

<style lang="scss" scoped>
.rh { width: 100%; height: 100%; overflow: auto; background: #1b1a20; }
</style>
