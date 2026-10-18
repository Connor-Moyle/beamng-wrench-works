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
          <div v-if="shown(f)" class="mm-row" :class="{ changed: f.changed }">
            <template v-if="f.type === 'heading'"><h4 class="mm-sub">{{ f.label }}</h4></template>
            <template v-else-if="f.type === 'note'"><p class="mm-note">{{ f.label }}</p></template>
            <template v-else>
              <div class="mm-label">
                <b>{{ f.label }}</b>
                <span v-if="f.changed" class="mm-dot" title="Different from the start value">changed</span>
                <span v-if="f.apply && f.apply !== 'live'" class="mm-apply">{{ applyText(f.apply) }}</span>
                <small v-if="f.tooltip">{{ f.tooltip }}</small>
              </div>
              <div class="mm-control">
                <template v-if="f.type === 'bool'">
                  <BngSwitch :modelValue="f.value" :label="f.value ? 'On' : 'Off'" labelBefore @valueChanged="v => change(f, v)" />
                </template>
                <template v-else-if="f.type === 'slider'">
                  <BngSlider
                    :modelValue="shownValue(f)"
                    :min="f.min * scale(f)"
                    :max="f.max * scale(f)"
                    :step="(f.step || (f.max - f.min) / 100) * scale(f)"
                    withInput
                    @valueChanged="v => change(f, v / scale(f))"
                  />
                  <span v-if="f.unit" class="mm-unit">{{ f.unit }}</span>
                </template>
                <template v-else-if="f.type === 'int'">
                  <button class="mm-step" bng-nav-item aria-label="less" @click="change(f, f.value - 1)">&minus;</button>
                  <span class="mm-num">{{ f.value }}</span>
                  <button class="mm-step" bng-nav-item aria-label="more" @click="change(f, f.value + 1)">+</button>
                </template>
                <template v-else-if="f.type === 'enum'">
                  <div class="mm-pills">
                    <button
                      v-for="o in f.options"
                      :key="o.id"
                      class="mm-pill"
                      :class="{ on: o.id === f.value }"
                      :aria-pressed="o.id === f.value"
                      bng-nav-item
                      @click="change(f, o.id)"
                    >{{ o.label }}</button>
                  </div>
                </template>
                <template v-else-if="f.type === 'color'">
                  <span class="mm-swatch" :style="{ background: css(f.value) }"></span>
                  <label v-for="k in ['r', 'g', 'b']" :key="k" class="mm-ch">{{ k.toUpperCase() }}
                    <input type="range" min="0" max="1" step="0.01" :value="f.value[k]" bng-nav-item @change="e => changeChannel(f, k, e.target.value)" />
                  </label>
                </template>
                <template v-else-if="f.type === 'texture'">
                  <div class="mm-tex">
                    <button v-if="f.none" class="mm-tile" :class="{ on: !f.value }" bng-nav-item @click="change(f, '')">None</button>
                    <button
                      v-for="file in f.files"
                      :key="file"
                      class="mm-tile"
                      :class="{ on: file === f.value }"
                      :title="file"
                      bng-nav-item
                      @click="change(f, file)"
                    ><span class="mm-thumb" :style="f.thumbs ? { backgroundImage: 'url(' + file + ')' } : {}"></span>{{ name(file) }}</button>
                  </div>
                </template>
                <template v-else-if="f.type === 'button'">
                  <span v-if="confirmField === f.id" class="mm-confirm">
                    {{ f.confirm }}
                    <button class="mm-btn danger" bng-nav-item @click="confirmField = ''; press(f)">Yes, do it</button>
                    <button class="mm-btn" bng-nav-item @click="confirmField = ''">Cancel</button>
                  </span>
                  <button v-else class="mm-btn" bng-nav-item @click="f.confirm ? (confirmField = f.id) : press(f)">{{ f.label }}</button>
                </template>
                <template v-else-if="f.type === 'text'">
                  <input class="mm-text" type="text" :value="f.value" :maxlength="f.maxLength || 80" @change="e => change(f, e.target.value)" />
                </template>
              </div>
            </template>
          </div>
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
import { BngSwitch, BngSlider } from "@/common/components/base"

const props = defineProps({ mod: String })

const info = ref(null)
const tab = ref("")
const fields = ref([])
const busy = ref(false)
const error = ref("")
const showAdvanced = ref(false)
const confirming = ref(false)
const confirmField = ref("")      // a button that asks first (a field's `confirm` text)
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
function scale(f) { return f.scale || 1 }
function shownValue(f) { return Math.round(f.value * scale(f) * 1e6) / 1e6 }
function css(c) { return `rgb(${Math.round((c.r || 0) * 255)},${Math.round((c.g || 0) * 255)},${Math.round((c.b || 0) * 255)})` }
function name(file) { return String(file).split("/").pop() }
function applyText(a) { return a === "spawn" ? "applies to cars spawned afterwards" : a === "restart" ? "applies after a restart" : "" }

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
    await openTab(info.value.tabs[0].id)
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

async function change(f, value) {
  const r = await lua.extensions.slrr_settings.set(props.mod, f.id, value)
  if (r && r.ok) {
    f.value = r.value
    f.changed = JSON.stringify(r.value) !== JSON.stringify(f.default)
    if (f.type === "enum") await openTab(tab.value)      // (a preset may have filled other fields)
  } else if (r) {
    toast(r.error || "That value was not accepted.")
    if (r.value !== undefined) f.value = r.value
  }
}

function changeChannel(f, key, v) {
  change(f, { ...f.value, [key]: Number(v) })
}

async function press(f) {
  const r = await lua.extensions.slrr_settings.press(props.mod, f.id)
  toast(r && (r.text || r.error))
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
.mm-tab, .mm-btn, .mm-pill, .mm-tile, .mm-step {
  background: #2c2a33; color: #ece9f1; border: 2px solid #4a4753; border-radius: 0.5rem; padding: 0.45rem 0.9rem; font: inherit; cursor: pointer;
}
.mm-tab.on, .mm-pill.on, .mm-tile.on { background: #a8c7fa; color: #062e6f; border-color: #a8c7fa; font-weight: 600; }
.mm-tab.on::before, .mm-pill.on::before { content: "\2713\00a0"; }
.mm-btn.danger { background: #ffb4ab; color: #410002; border-color: #ffb4ab; }
button:focus-visible, input:focus-visible, [bng-nav-item]:focus { outline: 3px solid #ffd54f; outline-offset: 2px; }
.mm-desc { margin: 0 0 0.75rem; color: #cfcbd8; }
.mm-bar { display: flex; flex-wrap: wrap; gap: 1rem; align-items: center; justify-content: space-between; margin-bottom: 1rem; }
.mm-adv { color: #cfcbd8; }
.mm-confirm { display: inline-flex; gap: 0.5rem; align-items: center; flex-wrap: wrap; }
.mm-group { margin-bottom: 1.25rem; }
.mm-gtitle { margin: 0 0 0.5rem; padding-bottom: 0.25rem; border-bottom: 2px solid #4a4753; font-size: 1.15rem; }
.mm-sub { margin: 0.75rem 0 0.25rem; font-size: 1rem; color: #cfcbd8; }
.mm-row { display: grid; grid-template-columns: minmax(12rem, 1fr) minmax(14rem, 1.4fr); gap: 1rem; align-items: center; padding: 0.55rem 0.6rem; border-radius: 0.5rem; }
.mm-row:hover { background: #24222a; }
.mm-row.changed { border-left: 4px solid #a8c7fa; }
.mm-label { display: flex; flex-direction: column; gap: 0.15rem; }
.mm-label small { color: #cfcbd8; font-size: 0.85rem; }
.mm-dot { font-size: 0.75rem; color: #a8c7fa; }
.mm-apply { font-size: 0.75rem; color: #ffd8a8; }
.mm-control { display: flex; align-items: center; gap: 0.6rem; flex-wrap: wrap; }
.mm-pills, .mm-tex { display: flex; flex-wrap: wrap; gap: 0.4rem; }
.mm-tile { display: flex; flex-direction: column; align-items: center; gap: 0.25rem; font-size: 0.8rem; max-width: 7rem; }
.mm-thumb { display: block; width: 5rem; height: 3.2rem; background: #17161b center / cover no-repeat; border-radius: 0.3rem; }
.mm-swatch { width: 2.2rem; height: 2.2rem; border: 2px solid #ece9f1; border-radius: 0.4rem; }
.mm-ch { display: inline-flex; flex-direction: column; font-size: 0.75rem; }
.mm-num { min-width: 2rem; text-align: center; font-weight: 600; }
.mm-text { background: #17161b; color: #ece9f1; border: 2px solid #4a4753; border-radius: 0.4rem; padding: 0.4rem 0.6rem; font: inherit; }
.mm-note { color: #cfcbd8; margin: 0.4rem 0; }
.mm-unit { color: #cfcbd8; }
.mm-toast { position: sticky; bottom: 0.5rem; margin-top: 1rem; padding: 0.6rem 1rem; background: #a8c7fa; color: #062e6f; border-radius: 0.5rem; font-weight: 600; }
@media (max-width: 900px) { .mm-row { grid-template-columns: 1fr; } }
</style>
