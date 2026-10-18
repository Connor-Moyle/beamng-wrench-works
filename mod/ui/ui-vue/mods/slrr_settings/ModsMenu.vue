<template>
  <div class="mm">
    <div v-if="error" class="mm-error">{{ error }}</div>
    <template v-else-if="info">
      <h2 class="mm-title">{{ info.title }}</h2>

      <div class="mm-tabs" role="tablist">
        <button
          v-for="t in info.tabs"
          :key="t.id"
          class="mm-tab"
          :class="{ on: t.id === tab }"
          role="tab"
          :aria-selected="t.id === tab"
          bng-nav-item
          @click="openTab(t.id)"
        >{{ t.title }}</button>
      </div>

      <p v-if="tabInfo && tabInfo.description" class="mm-desc">{{ tabInfo.description }}</p>

      <div class="mm-bar">
        <label class="mm-adv">
          <input type="checkbox" v-model="showAdvanced" bng-nav-item /> Show advanced settings
        </label>
        <button v-if="!confirming" class="mm-btn" bng-nav-item @click="confirming = true">Reset this tab to defaults</button>
        <span v-else class="mm-confirm">
          Put every setting of this tab back to its start value?
          <button class="mm-btn danger" bng-nav-item @click="resetTab">Yes, reset</button>
          <button class="mm-btn" bng-nav-item @click="confirming = false">Cancel</button>
        </span>
      </div>

      <div v-if="busy" class="mm-note">Loading ...</div>
      <div v-for="g in groups" :key="g.name" class="mm-group">
        <h3 v-if="g.name" class="mm-gtitle">{{ g.name }}</h3>
        <template v-for="f in g.fields" :key="f.id">
          <SettingRow v-if="shown(f)" :mod="mod" :field="f" @reload="openTab(tab)" @toast="toast" />
        </template>
      </div>
      <div v-if="toastText" class="mm-toast">{{ toastText }}</div>
    </template>
    <div v-else class="mm-note">Loading ...</div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from "vue"
import { lua } from "@/bridge"
import SettingRow from "./SettingRow.vue"

const props = defineProps({ mod: String, startTab: String })

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
    if (f.advanced && !showAdvanced.value) continue
    const name = f.group || ""
    let g = out.find(x => x.name === name)
    if (!g) { g = { name, fields: [] }; out.push(g) }
    g.fields.push(f)
  }
  return out
})

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
    const mods = await lua.extensions.slrr_settings.mods()
    info.value = (mods || []).find(m => m.mod === props.mod) || null
    if (!info.value) { error.value = "This mod has no settings page (is it installed?)."; return }
    const wanted = info.value.tabs.find(t => t.id === props.startTab)
    await openTab((wanted || info.value.tabs[0]).id)
  } catch (e) {
    error.value = "The settings could not be read: " + e
  }
}

async function openTab(id) {
  tab.value = id
  confirming.value = false
  busy.value = true
  try {
    const page = await lua.extensions.slrr_settings.page(props.mod, id)
    fields.value = (page && page.fields) || []
  } finally {
    busy.value = false
  }
}

async function resetTab() {
  confirming.value = false
  const page = await lua.extensions.slrr_settings.reset(props.mod, tab.value)
  fields.value = (page && page.fields) || []
  toast("This tab is back to its start values.")
}

onMounted(load)
</script>

<style lang="scss" scoped>
// dark card colours; text on them is at least 7:1 (WCAG AAA) and state is never only a colour
.mm { padding: 1rem 1.25rem; color: #ece9f1; max-width: 62rem; margin: 0 auto; font-size: 1rem; line-height: 1.4; }
.mm-title { margin: 0 0 0.75rem; font-size: 1.5rem; font-weight: 600; }
.mm-error { padding: 1rem; border: 2px solid #ffb4ab; border-radius: 0.5rem; color: #ffdad6; }
.mm-tabs { display: flex; flex-wrap: wrap; gap: 0.4rem; margin-bottom: 0.75rem; }
.mm-tab, .mm-btn { background: #2c2a33; color: #ece9f1; border: 2px solid #4a4753; border-radius: 0.5rem; padding: 0.45rem 0.9rem; font: inherit; cursor: pointer; }
.mm-tab.on { background: #a8c7fa; color: #062e6f; border-color: #a8c7fa; font-weight: 600; }
.mm-tab.on::before { content: "\2713\00a0"; }
.mm-btn.danger { background: #ffb4ab; color: #410002; border-color: #ffb4ab; }
button:focus-visible, input:focus-visible, [bng-nav-item]:focus { outline: 3px solid #ffd54f; outline-offset: 2px; }
.mm-desc { margin: 0 0 0.75rem; color: #cfcbd8; }
.mm-bar { display: flex; flex-wrap: wrap; gap: 1rem; align-items: center; justify-content: space-between; margin-bottom: 1rem; }
.mm-adv { color: #cfcbd8; }
.mm-confirm { display: inline-flex; gap: 0.5rem; align-items: center; flex-wrap: wrap; }
.mm-group { margin-bottom: 1.25rem; }
.mm-gtitle { margin: 0 0 0.5rem; padding-bottom: 0.25rem; border-bottom: 2px solid #4a4753; font-size: 1.15rem; }
.mm-note { color: #cfcbd8; margin: 0.4rem 0; }
.mm-toast { position: sticky; bottom: 0.5rem; margin-top: 1rem; padding: 0.6rem 1rem; background: #a8c7fa; color: #062e6f; border-radius: 0.5rem; font-weight: 600; }
</style>
