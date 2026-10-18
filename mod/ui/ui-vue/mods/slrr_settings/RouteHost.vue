<template>
  <!-- the whole Mods menu as one screen, laid out like Options: a column of pages (Quick setup, Find a setting, each mod), and the chosen page beside it -->
  <div class="rh options-container">
    <div class="rh-rail options-subcategories">
      <h3 class="rh-title">Mods menu</h3>
      <Button class="options-category-side" :class="{ selected: page === 'quick' }" @pointerdown="show('quick')" @click="show('quick')">Quick setup</Button>
      <Button class="options-category-side" :class="{ selected: page === 'find' }" @pointerdown="show('find')" @click="show('find')">Find a setting</Button>
      <div class="rh-divider"></div>
      <Button
        v-for="m in mods"
        :key="m.mod"
        class="options-category-side"
        :class="{ selected: page === 'mod' && mod === m.mod }"
        @pointerdown="show('mod', m.mod)"
        @click="show('mod', m.mod)"
      >{{ m.title }}</Button>
    </div>
    <div class="rh-page">
      <ModsMenu v-if="page === 'mod'" :mod="mod" :startTab="tab" full :key="mod + '/' + tab" />
      <FindSetting v-else-if="page === 'find'" full />
      <QuickSetup v-else full />
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onBeforeUnmount } from "vue"
import { useRoute } from "vue-router"
import { Button } from "@/common/components/utility"
import { call, holdPause } from "./settingsApi.js"
import ModsMenu from "./ModsMenu.vue"
import FindSetting from "./FindSetting.vue"
import QuickSetup from "./QuickSetup.vue"

// the Mods menu pages as a screen of its own (route menu.slrrMods); the pause menu cards open it. Also how the in-game check opens a page without a click:
// extensions.ui_router.navigate('menu.slrrMods', { page = 'mod', mod = 'car_surface_fx', tab = 'rain' })   (page: mod | find | quick)
const route = useRoute()
const page = ref(String(route.params.page || "quick"))
const mod = ref(String(route.params.mod || ""))
const tab = ref(String(route.params.tab || ""))
const mods = ref([])

function show(p, m) {
  if (p === page.value && (p !== "mod" || m === mod.value)) return
  page.value = p
  mod.value = m || ""
  tab.value = ""
}

onMounted(() => holdPause(true))
onBeforeUnmount(() => holdPause(false))
onMounted(async () => { try { mods.value = (await call("mods")) || [] } catch (e) { mods.value = [] } })
</script>

<style lang="scss" scoped>
.rh { display: flex; width: 100%; height: 100%; overflow: hidden; font-family: "Overpass", var(--fnt-defs); }
.rh-rail { flex: 0 0 auto; display: flex; flex-direction: column; width: 14em; padding: 1em 0.25em; overflow-y: auto; background: color-mix(in srgb, var(--bng-off-black) 90%, transparent); border-right: 0.125em solid var(--bng-orange-550); }
.rh-title { margin: 0 0.4em 0.6em; font-size: 1.15em; font-weight: 600; color: var(--bng-off-white); }
.rh-divider { height: 1px; margin: 0.5em 0.75em; background: var(--bng-orange-600); opacity: 0.6; }
.options-category-side {
  position: relative; display: flex; align-items: flex-start; justify-content: flex-start; text-align: left; padding: 0.25em 0.5em; margin-bottom: 0.1em;
  --bng-bg-enabled: transparent; --bng-bg-hover: var(--bng-orange-500); --bng-bg-active: var(--bng-orange-600); --bng-bg-border-radius: var(--bng-corners-2); --bng-bg-border-width: 0.125em;
  &.selected { --bng-bg-enabled: var(--bng-orange-550); --bng-bg-hover: var(--bng-orange-400); --bng-bg-border-radius: var(--bng-corners-2) 0 0 var(--bng-corners-2); }
  &.selected :deep(.bng-background) { right: -0.5em; }
}
.rh-page { flex: 1 1 auto; min-width: 0; overflow: auto; background: color-mix(in srgb, var(--bng-off-black) 90%, transparent); color: var(--bng-off-white); }
</style>
