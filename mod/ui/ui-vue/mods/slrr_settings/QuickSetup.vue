<template>
  <div class="mq">
    <h2 class="mq-title">Quick setup</h2>
    <p class="mq-desc">One choice for the whole pack: it sets the settings that matter for how smooth the game runs and how good it looks, in every mod that has them. Pick the one that suits your computer; you can still change any single setting afterwards, and then this shows Custom.</p>

    <div class="mq-pills" role="radiogroup" aria-label="Quick setup">
      <button
        v-for="p in presets"
        :key="p.id"
        class="mq-pill"
        :class="{ on: p.id === current }"
        role="radio"
        :aria-checked="p.id === current"
        :disabled="!p.fields"
        bng-nav-item
        @click="apply(p.id)"
      >{{ p.title }}</button>
      <span class="mq-pill custom" :class="{ on: current === 'custom' }" aria-live="polite">Custom<span v-if="current === 'custom'"> (you changed something)</span></span>
    </div>

    <p v-if="current === 'none'" class="mq-note">None of the installed mods has a quick setup yet.</p>
    <p v-else-if="applied" class="mq-note">{{ applied }}</p>

    <h3 v-if="mods.length" class="mq-sub">What a quick setup changes</h3>
    <ul v-if="mods.length" class="mq-list">
      <li v-for="m in mods" :key="m.mod">{{ m.title }}: {{ m.fields }} {{ m.fields === 1 ? "setting" : "settings" }}</li>
    </ul>
  </div>
</template>

<script setup>
import { ref, onMounted } from "vue"
import { call, openFull } from "./settingsApi.js"

const props = defineProps({ full: Boolean })

const presets = ref([])
const mods = ref([])
const current = ref("none")
const applied = ref("")

function take(r) {
  presets.value = r.presets || []
  mods.value = r.mods || []
  current.value = r.current || "none"
}

async function apply(id) {
  let r
  try { r = await call("applyPreset", id) } catch (e) { applied.value = "The game did not answer: " + e.message; return }
  if (r && r.ok) {
    take(r)
    applied.value = `${r.changed} ${r.changed === 1 ? "setting was" : "settings were"} set. Some apply to cars spawned afterwards or after a restart.`
  } else {
    applied.value = (r && r.error) || "That did not work."
  }
}

onMounted(async () => {
  if (!props.full) openFull("quick")
  try { take((await call("quickSetup")) || {}) } catch (e) { applied.value = "The settings could not be read: " + e.message }
})
</script>

<style lang="scss" scoped>
.mq { padding: 1rem 1.25rem; color: #ece9f1; max-width: 62rem; margin: 0 auto; font-size: 1rem; line-height: 1.4; }
.mq-title { margin: 0 0 0.5rem; font-size: 1.5rem; font-weight: 600; }
.mq-desc { color: #cfcbd8; margin: 0 0 1rem; }
.mq-pills { display: flex; flex-wrap: wrap; gap: 0.5rem; }
.mq-pill { background: #2c2a33; color: #ece9f1; border: 2px solid #4a4753; border-radius: 0.5rem; padding: 0.7rem 1.4rem; font: inherit; font-size: 1.1rem; cursor: pointer; }
.mq-pill.custom { cursor: default; border-style: dashed; }
.mq-pill.on { background: #a8c7fa; color: #062e6f; border-color: #a8c7fa; font-weight: 600; }
.mq-pill.on::before { content: "\2713\00a0"; }
.mq-pill:disabled { opacity: 0.6; cursor: default; }
.mq-pill:focus-visible { outline: 3px solid #ffd54f; outline-offset: 2px; }
.mq-note { color: #cfcbd8; margin: 1rem 0; }
.mq-sub { margin: 1.25rem 0 0.4rem; font-size: 1.1rem; }
.mq-list { margin: 0; padding-left: 1.4rem; color: #cfcbd8; }
</style>
