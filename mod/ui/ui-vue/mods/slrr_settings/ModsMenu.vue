<template>
  <!-- laid out like the game's Options screen: the tab list on the left (the category column), the settings on the right (rows with the label left, the control right) -->
  <div ref="root" class="options-container mm" :class="{ narrow }">
    <div v-if="error" class="mm-error">{{ error }}</div>
    <template v-else-if="info">
      <div class="options-subcategories" role="tablist">
        <h3 class="mm-title">{{ info.title }}</h3>
        <Button
          v-for="t in info.tabs"
          :key="t.id"
          class="options-category-side"
          :class="{ selected: t.id === tab }"
          role="tab"
          :aria-selected="t.id === tab"
          @pointerdown="openTab(t.id)"
          @click="openTab(t.id)"
        >{{ t.title }}</Button>
      </div>

      <div class="options-content-wrapper">
        <div class="options-content-main">
          <div class="options-head">
            <p v-if="tabInfo && tabInfo.description" class="mm-desc">{{ tabInfo.description }}</p>
            <div class="mm-bar">
              <BngSwitch v-model="showAdvanced" label="Show advanced settings" labelBefore />
              <BngButton v-if="!confirming" @click="confirming = true">Reset this tab to defaults</BngButton>
              <span v-else class="mm-confirm">
                Put every setting of this tab back to its start value?
                <BngButton @click="resetTab">Yes, reset</BngButton>
                <BngButton @click="confirming = false">Cancel</BngButton>
              </span>
            </div>
          </div>

          <div class="options-content">
            <div v-if="busy" class="mm-note">Loading ...</div>
            <div v-if="!busy && hiddenCount" class="mm-note">{{ hiddenCount }} more setting{{ hiddenCount > 1 ? "s" : "" }} on this tab: switch on "Show advanced settings" above.</div>
            <div v-for="g in groups" :key="g.name" class="mm-group">
              <h4 v-if="g.name" class="mm-gtitle">{{ g.name }}</h4>
              <template v-for="f in g.fields" :key="f.id">
                <SettingRow v-if="shown(f)" :mod="mod" :field="f" :vertical="narrow" @reload="openTab(tab, true)" @toast="toast" />
              </template>
            </div>
          </div>
          <div v-if="toastText" class="mm-toast">{{ toastText }}</div>
        </div>
      </div>
    </template>
    <div v-else class="mm-note">Loading ...</div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from "vue"
import { call, openFull } from "./settingsApi.js"
import { BngButton, BngSwitch } from "@/common/components/base"
import { Button } from "@/common/components/utility"
import SettingRow from "./SettingRow.vue"

const props = defineProps({ mod: String, startTab: String, full: Boolean })

const info = ref(null)
const tab = ref("")
const fields = ref([])
const busy = ref(false)
const error = ref("")
const showAdvanced = ref(false)
const confirming = ref(false)
const toastText = ref("")
let toastTimer

const tabInfo = computed(() => (info.value ? info.value.tabs.find(t => t.id === tab.value) : null))

// the fields of the tab, in groups (a heading field starts its own sub-heading inside the group)
const groups = computed(() => {
  const out = []
  for (const f of fields.value) {
    if (f.advanced && !showAdvanced.value && !onlyAdvanced.value) continue
    const name = f.group || ""
    let g = out.find(x => x.name === name)
    if (!g) { g = { name, fields: [] }; out.push(g) }
    g.fields.push(f)
  }
  return out
})

// a tab whose settings are all advanced would show an empty page: it shows them
const onlyAdvanced = computed(() => fields.value.length > 0 && fields.value.every(f => f.advanced || f.type === "heading" || f.type === "note"))
const hiddenCount = computed(() => (showAdvanced.value || onlyAdvanced.value ? 0 : fields.value.filter(f => f.advanced).length))
const byId = computed(() => Object.fromEntries(fields.value.map(f => [f.id, f])))
function shown(f) {
  if (!f.visibleIf) return true
  const other = byId.value[f.visibleIf.field]
  return !other || other.value === f.visibleIf.equals
}

function toast(text) {
  if (!text) return
  toastText.value = text
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => (toastText.value = ""), 3500)
}

async function load() {
  try {
    const mods = await call("mods")
    info.value = (mods || []).find(m => m.mod === props.mod) || null
    if (!info.value) { error.value = "This mod has no settings page (is it installed?)."; return }
    const wanted = info.value.tabs.find(t => t.id === props.startTab)
    await openTab((wanted || info.value.tabs[0]).id)
  } catch (e) {
    error.value = "The settings could not be read: " + e
  }
}

// (selects on the press and again on the click: a click that only moved the focus ring still selects; the second call is skipped)
async function openTab(id, force) {
  if (!force && id === tab.value && fields.value.length) return
  tab.value = id
  confirming.value = false
  busy.value = true
  try {
    const page = await call("page", props.mod, id)
    fields.value = (page && page.fields) || []
  } catch (e) {
    error.value = "The settings could not be read: " + e.message
  } finally {
    busy.value = false
  }
}

async function resetTab() {
  confirming.value = false
  try {
    const page = await call("reset", props.mod, tab.value)
    fields.value = (page && page.fields) || []
    toast("This tab is back to its start values.")
  } catch (e) { toast("The game did not answer: " + e.message) }
}

// the pause menu gives a mod page a narrow card (about 450 px at 1080p): below 700 px the tab list goes on top and the rows stack (label above its control)
const root = ref(null)
const narrow = ref(false)
let watcher
onMounted(() => {
  // opened as a card of the pause menu (a narrow card): open the same page as a screen of its own, like Options (the route host passes `full`). If that fails the card stays as the fallback.
  if (!props.full) openFull("mod", props.mod, props.startTab)
  load()
  if (root.value && window.ResizeObserver) {
    watcher = new ResizeObserver(() => { narrow.value = root.value.clientWidth < 700 })
    watcher.observe(root.value)
  }
})
onBeforeUnmount(() => watcher && watcher.disconnect())
</script>

<style lang="scss" scoped>
// the look of the game's Options screen (OptionsBody.vue): a dark category column with an orange edge, an orange selected tab, a dark content column
.options-container { display: flex; flex-direction: row; flex-wrap: nowrap; align-items: stretch; width: 100%; max-width: 100%; height: 100%; overflow: hidden; font-family: "Overpass", var(--fnt-defs); }
.mm.narrow { flex-direction: column; }
.narrow .options-subcategories { flex-direction: row; flex-wrap: wrap; align-items: center; width: 100%; max-height: 9em; padding: 0.5em; border-right: 0; border-bottom: 0.125em solid var(--bng-orange-550); }
.narrow .mm-title { flex: 1 0 100%; margin: 0 0.2em 0.3em; }
.narrow .options-category-side { margin: 0.1em; &.selected { --bng-bg-border-radius: var(--bng-corners-2); } &.selected :deep(.bng-background) { right: 0; } }
.options-subcategories {
  flex: 0 0 auto; display: flex; flex-direction: column; width: 12em; padding: 1em 0.25em; overflow-y: auto;
  background: color-mix(in srgb, var(--bng-off-black) 90%, transparent); border-right: 0.125em solid var(--bng-orange-550);
}
.mm-title { margin: 0 0.4em 0.6em; font-size: 1.15em; font-weight: 600; color: var(--bng-off-white); }
.options-category-side {
  position: relative; display: flex; align-items: flex-start; justify-content: flex-start; text-align: left; padding: 0.25em 0.5em; max-width: 20em; margin-bottom: 0.1em;
  --bng-bg-enabled: transparent; --bng-bg-hover: var(--bng-orange-500); --bng-bg-active: var(--bng-orange-600); --bng-bg-border-radius: var(--bng-corners-2); --bng-bg-border-width: 0.125em;
  &.selected { --bng-bg-enabled: var(--bng-orange-550); --bng-bg-hover: var(--bng-orange-400); --bng-bg-border-radius: var(--bng-corners-2) 0 0 var(--bng-corners-2); }
  &.selected :deep(.bng-background) { right: -0.5em; }
}
.options-content-wrapper { flex: 1 1 auto; display: flex; min-width: 0; background: color-mix(in srgb, var(--bng-off-black) 90%, transparent); }
.options-content-main { flex: 1 1 auto; display: flex; flex-direction: column; min-height: 0; min-width: 0; overflow: hidden; }
.options-head { flex: 0 0 auto; padding: 0.75em 0.75em 0.25em; }
.options-content { flex: 1 1 auto; min-height: 0; overflow-y: auto; padding: 0.25em 0.75em 1em; }
.mm-desc { margin: 0 0 0.5em; color: var(--bng-cool-gray-100, #cfcbd8); }
// (left-aligned: the career HUD sits over the top right corner)
.mm-bar { display: flex; flex-wrap: wrap; gap: 1em; align-items: center; }
.mm-confirm { display: inline-flex; gap: 0.5em; align-items: center; flex-wrap: wrap; }
.mm-group { margin-bottom: 0.75em; }
.mm-gtitle { margin: 0.25em 0 0.5em; font-family: "Overpass", var(--fnt-defs); color: var(--bng-off-white); }
.mm-note { color: var(--bng-cool-gray-100, #cfcbd8); margin: 0.4em 0; }
.mm-error { padding: 1em; border: 2px solid #ffb4ab; border-radius: 0.5em; color: #ffdad6; }
.mm-toast { flex: 0 0 auto; margin: 0.5em 0.75em; padding: 0.5em 1em; background: var(--bng-orange-550); color: var(--bng-off-white); border-radius: var(--bng-corners-2); font-weight: 600; }
</style>
