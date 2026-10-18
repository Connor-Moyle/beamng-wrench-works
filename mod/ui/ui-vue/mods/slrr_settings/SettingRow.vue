<template>
  <div class="mm-row" :class="{ changed: field.changed }">
    <template v-if="field.type === 'heading'"><h4 class="mm-sub">{{ field.label }}</h4></template>
    <template v-else-if="field.type === 'note'"><p class="mm-note">{{ field.label }}</p></template>
    <template v-else>
      <div class="mm-label">
        <b>{{ field.label }}</b>
        <span v-if="field.changed" class="mm-dot" title="Different from the start value">changed</span>
        <span v-if="field.apply && field.apply !== 'live'" class="mm-apply">{{ applyText(field.apply) }}</span>
        <span v-if="field.requires === 'career'" class="mm-apply">changes only while a career is loaded</span>
        <small v-if="field.tooltip">{{ field.tooltip }}</small>
      </div>
      <div class="mm-control">
        <template v-if="field.type === 'bool'">
          <BngSwitch :modelValue="field.value" :label="field.value ? 'On' : 'Off'" labelBefore @valueChanged="onSwitch" />
        </template>
        <template v-else-if="field.type === 'slider'">
          <BngSlider
            :modelValue="shownValue()"
            :min="field.min * scale()"
            :max="field.max * scale()"
            :step="(field.step || (field.max - field.min) / 100) * scale()"
            withInput
            @valueChanged="onSlider"
          />
          <span v-if="field.unit" class="mm-unit">{{ field.unit }}</span>
        </template>
        <template v-else-if="field.type === 'int'">
          <button class="mm-step" bng-nav-item aria-label="less" @click="change(field.value - 1)">&minus;</button>
          <span class="mm-num">{{ field.value }}</span>
          <button class="mm-step" bng-nav-item aria-label="more" @click="change(field.value + 1)">+</button>
        </template>
        <template v-else-if="field.type === 'enum'">
          <div class="mm-pills">
            <button
              v-for="o in field.options"
              :key="o.id"
              class="mm-pill"
              :class="{ on: o.id === field.value }"
              :aria-pressed="o.id === field.value"
              bng-nav-item
              @click="change(o.id)"
            >{{ o.label }}</button>
          </div>
        </template>
        <template v-else-if="field.type === 'color'">
          <span class="mm-swatch" :style="{ background: css(field.value) }"></span>
          <label v-for="k in ['r', 'g', 'b']" :key="k" class="mm-ch">{{ k.toUpperCase() }}
            <input type="range" min="0" max="1" step="0.01" :value="field.value[k]" bng-nav-item @change="e => changeChannel(k, e.target.value)" />
          </label>
        </template>
        <template v-else-if="field.type === 'texture'">
          <div class="mm-tex">
            <button v-if="field.none" class="mm-tile" :class="{ on: !field.value }" bng-nav-item @click="change('')">None</button>
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
            <button class="mm-btn danger" bng-nav-item @click="asking = false; press()">Yes, do it</button>
            <button class="mm-btn" bng-nav-item @click="asking = false">Cancel</button>
          </span>
          <button v-else class="mm-btn" bng-nav-item @click="field.confirm ? (asking = true) : press()">{{ field.label }}</button>
        </template>
        <template v-else-if="field.type === 'text'">
          <input class="mm-text" type="text" :value="field.value" :maxlength="field.maxLength || 80" @change="e => change(e.target.value)" />
        </template>
      </div>
    </template>
  </div>
</template>

<script setup>
import { ref } from "vue"
import { call } from "./settingsApi.js"
import { BngSwitch, BngSlider } from "@/common/components/base"

// One setting of a mod: its label, tooltip and the control for its type. The Mods menu pages and the search results both show it.
const props = defineProps({ mod: String, field: Object })
const emit = defineEmits(["reload", "toast"])
const asking = ref(false)

function scale() { return props.field.scale || 1 }
function shownValue() { return Math.round(props.field.value * scale() * 1e6) / 1e6 }
function css(c) { return `rgb(${Math.round((c.r || 0) * 255)},${Math.round((c.g || 0) * 255)},${Math.round((c.b || 0) * 255)})` }
function fileName(file) { return String(file).split("/").pop() }
function applyText(a) { return a === "spawn" ? "applies to cars spawned afterwards" : a === "restart" ? "applies after a restart" : "" }

async function change(value) {
  const f = props.field
  const r = await call("set", props.mod, f.id, value)
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
function onSlider(v) { change(v / scale()) }
function changeChannel(key, v) { change({ ...props.field.value, [key]: Number(v) }) }

async function press() {
  const r = await call("press", props.mod, props.field.id)
  emit("toast", r && (r.text || r.error))
}
</script>

<style lang="scss" scoped>
.mm-row { display: grid; grid-template-columns: minmax(12rem, 1fr) minmax(14rem, 1.4fr); gap: 1rem; align-items: center; padding: 0.55rem 0.6rem; border-radius: 0.5rem; color: #ece9f1; }
.mm-row:hover { background: #24222a; }
.mm-row.changed { border-left: 4px solid #a8c7fa; }
.mm-label { display: flex; flex-direction: column; gap: 0.15rem; }
.mm-label small { color: #cfcbd8; font-size: 0.85rem; }
.mm-dot { font-size: 0.75rem; color: #a8c7fa; }
.mm-apply { font-size: 0.75rem; color: #ffd8a8; }
.mm-control { display: flex; align-items: center; gap: 0.6rem; flex-wrap: wrap; }
.mm-pills, .mm-tex { display: flex; flex-wrap: wrap; gap: 0.4rem; }
.mm-btn, .mm-pill, .mm-tile, .mm-step { background: #2c2a33; color: #ece9f1; border: 2px solid #4a4753; border-radius: 0.5rem; padding: 0.45rem 0.9rem; font: inherit; cursor: pointer; }
.mm-pill.on, .mm-tile.on { background: #a8c7fa; color: #062e6f; border-color: #a8c7fa; font-weight: 600; }
.mm-pill.on::before { content: "\2713\00a0"; }
.mm-btn.danger { background: #ffb4ab; color: #410002; border-color: #ffb4ab; }
button:focus-visible, input:focus-visible, [bng-nav-item]:focus { outline: 3px solid #ffd54f; outline-offset: 2px; }
.mm-confirm { display: inline-flex; gap: 0.5rem; align-items: center; flex-wrap: wrap; }
.mm-tile { display: flex; flex-direction: column; align-items: center; gap: 0.25rem; font-size: 0.8rem; max-width: 7rem; }
.mm-thumb { display: block; width: 5rem; height: 3.2rem; background: #17161b center / cover no-repeat; border-radius: 0.3rem; }
.mm-swatch { width: 2.2rem; height: 2.2rem; border: 2px solid #ece9f1; border-radius: 0.4rem; }
.mm-ch { display: inline-flex; flex-direction: column; font-size: 0.75rem; }
.mm-num { min-width: 2rem; text-align: center; font-weight: 600; }
.mm-text { background: #17161b; color: #ece9f1; border: 2px solid #4a4753; border-radius: 0.4rem; padding: 0.4rem 0.6rem; font: inherit; }
.mm-sub { margin: 0.75rem 0 0.25rem; font-size: 1rem; color: #cfcbd8; }
.mm-note { color: #cfcbd8; margin: 0.4rem 0; }
.mm-unit { color: #cfcbd8; }
@media (max-width: 900px) { .mm-row { grid-template-columns: 1fr; } }
</style>
