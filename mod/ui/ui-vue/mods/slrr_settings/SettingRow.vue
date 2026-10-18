<template>
  <!-- one setting laid out like a row of the game's Options screen: the label (and its note) on the left, the control on the right -->
  <h4 v-if="field.type === 'heading'" class="options-item-heading mm-sub">{{ field.label }}</h4>
  <p v-else-if="field.type === 'note'" class="mm-note">{{ field.label }}</p>
  <div v-else class="options-item" :class="{ changed: field.changed }">
    <BngRow class="options-item-row" :vertical="vertical">
      <template #label>
        <div class="options-item-label">
          <span class="options-item-label-text">{{ field.label }}</span>
          <span v-if="field.changed" class="mm-tag" title="Different from the start value">changed</span>
          <span v-if="field.apply && field.apply !== 'live'" class="mm-tag mm-apply">{{ applyText(field.apply) }}</span>
          <span v-if="field.requires === 'career'" class="mm-tag mm-apply">changes only while a career is loaded</span>
        </div>
        <small v-if="field.tooltip" class="mm-help">{{ field.tooltip }}</small>
      </template>

      <BngSwitch v-if="field.type === 'bool'" :modelValue="field.value" @valueChanged="onSwitch" />
      <template v-else-if="field.type === 'slider'">
        <BngSlider
          :modelValue="shownValue()"
          :min="field.min * scale()"
          :max="field.max * scale()"
          :step="(field.step || (field.max - field.min) / 100) * scale()"
          :unit="field.unit"
          withInput
          @valueChanged="onSlider"
        />
      </template>
      <template v-else-if="field.type === 'int'">
        <div class="mm-int">
          <BngButton aria-label="less" @click="change(field.value - 1)">&minus;</BngButton>
          <span class="mm-num">{{ field.value }}</span>
          <BngButton aria-label="more" @click="change(field.value + 1)">+</BngButton>
        </div>
      </template>
      <BngSmartSelect v-else-if="field.type === 'enum'" :modelValue="field.value" :items="items()" @change="change" />
      <template v-else-if="field.type === 'color'">
        <div class="mm-color">
          <span class="mm-swatch" :style="{ background: css(field.value) }"></span>
          <label v-for="k in ['r', 'g', 'b']" :key="k" class="mm-ch">{{ k.toUpperCase() }}
            <input type="range" min="0" max="1" step="0.01" :value="field.value[k]" bng-nav-item @change="e => changeChannel(k, e.target.value)" />
          </label>
        </div>
      </template>
      <template v-else-if="field.type === 'texture'">
        <div class="mm-tex">
          <BngButton v-if="field.none" :class="{ on: !field.value }" @click="change('')">None</BngButton>
          <button
            v-for="file in field.files"
            :key="file"
            class="mm-tile"
            :class="{ on: file === field.value }"
            :title="file"
            bng-nav-item
            @click="change(file)"
          ><span class="mm-thumb" :style="field.thumbs ? { backgroundImage: 'url(' + file + ')' } : {}"></span>{{ fileName(file) }}</button>
        </div>
      </template>
      <template v-else-if="field.type === 'button'">
        <span v-if="asking" class="mm-confirm">
          {{ field.confirm }}
          <BngButton @click="asking = false; press()">Yes, do it</BngButton>
          <BngButton @click="asking = false">Cancel</BngButton>
        </span>
        <BngButton v-else @click="field.confirm ? (asking = true) : press()">{{ field.label }}</BngButton>
      </template>
      <BngInput v-else-if="field.type === 'text'" :modelValue="field.value" :maxlength="field.maxLength || 80" @change="change" />
    </BngRow>
  </div>
</template>

<script setup>
import { ref } from "vue"
import { call } from "./settingsApi.js"
import { BngSwitch, BngSlider, BngRow, BngButton, BngInput, BngSmartSelect } from "@/common/components/base"

// One setting of a mod: its label, tooltip and the control for its type. The Mods menu pages and the search results both show it.
const props = defineProps({ mod: String, field: Object, vertical: Boolean })
const emit = defineEmits(["reload", "toast"])
const asking = ref(false)

function scale() { return props.field.scale || 1 }
function shownValue() { return Math.round(props.field.value * scale() * 1e6) / 1e6 }
function css(c) { return `rgb(${Math.round((c.r || 0) * 255)},${Math.round((c.g || 0) * 255)},${Math.round((c.b || 0) * 255)})` }
function fileName(file) { return String(file).split("/").pop() }
function applyText(a) { return a === "spawn" ? "applies to cars spawned afterwards" : a === "restart" ? "applies after a restart" : "" }

async function change(value) {
  const f = props.field
  let r
  try { r = await call("set", props.mod, f.id, value) } catch (e) { emit("toast", "The game did not answer: " + e.message); return }
  if (r && r.ok) {
    f.value = r.value
    f.changed = JSON.stringify(r.value) !== JSON.stringify(f.default)
    if (f.type === "enum") emit("reload")      // (a preset may have filled other fields)
  } else if (r) {
    emit("toast", r.error || "That value was not accepted.")
    if (r.value !== undefined) f.value = r.value
  }
}
function onSwitch(v) { change(v) }
// a slider sends a value for every step of a drag: only the last one is written (like the game's own sliders)
let sliderTimer
function onSlider(v) { clearTimeout(sliderTimer); sliderTimer = setTimeout(() => change(v / scale()), 400) }
function items() { return (props.field.options || []).map(o => ({ value: o.id, label: o.label })) }
function changeChannel(key, v) { change({ ...props.field.value, [key]: Number(v) }) }

async function press() {
  try {
    const r = await call("press", props.mod, props.field.id)
    emit("toast", r && (r.text || r.error))
  } catch (e) { emit("toast", "The game did not answer: " + e.message) }
}
</script>

<style lang="scss" scoped>
// the Options look comes from BngRow and the base controls; only what they lack is here
.options-item { position: relative; display: block; padding: 0.125em; }
.options-item.changed :deep(.bng-row-label) { border-left: 3px solid var(--bng-orange-500); }
.options-item-label { display: flex; align-items: center; flex-wrap: wrap; gap: 0.4em; width: 100%; }
.mm-help { display: block; margin-top: 0.1em; font-size: 0.85em; color: var(--bng-cool-gray-100, #cfcbd8); }
.mm-tag { font-size: 0.75em; color: var(--bng-orange-300, #ffb070); }
.mm-apply { color: #ffd8a8; }
.mm-sub { margin: 0.75em 0 0.4em; font-family: "Overpass", var(--fnt-defs); color: var(--bng-off-white); }
.mm-note { color: var(--bng-cool-gray-100, #cfcbd8); margin: 0.4em 0; }
.mm-int, .mm-color, .mm-tex { display: flex; align-items: center; flex-wrap: wrap; gap: 0.5em; }
.mm-num { min-width: 2em; text-align: center; font-weight: 600; }
.mm-tile { display: flex; flex-direction: column; align-items: center; gap: 0.25em; font-size: 0.8em; max-width: 7em; padding: 0.4em 0.6em; font: inherit; color: var(--bng-off-white); background: var(--bng-cool-gray-700); border: 2px solid transparent; border-radius: var(--bng-corners-2); cursor: pointer; }
.mm-tile:hover { background: var(--bng-cool-gray-600); }
.mm-tile.on { border-color: var(--bng-orange-500); }
.mm-thumb { display: block; width: 5em; height: 3.2em; background: var(--bng-off-black) center / cover no-repeat; border-radius: 0.3em; }
.mm-swatch { width: 2em; height: 2em; border: 2px solid var(--bng-off-white); border-radius: 0.4em; }
.mm-ch { display: inline-flex; flex-direction: column; font-size: 0.75em; }
.mm-confirm { display: inline-flex; gap: 0.5em; align-items: center; flex-wrap: wrap; }
</style>
