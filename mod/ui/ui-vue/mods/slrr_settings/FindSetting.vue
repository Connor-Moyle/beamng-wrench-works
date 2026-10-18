<template>
  <div class="mf">
    <h2 class="mf-title">Find a setting</h2>
    <p class="mf-desc">Type a word of what you are looking for: it searches the names and the descriptions of the settings of all our mods. The settings you find can be changed right here.</p>
    <input
      class="mf-input"
      type="text"
      v-model="query"
      placeholder="for example: rain, traffic, shadows"
      aria-label="Search the settings"
      bng-nav-item
      @input="search"
    />
    <p v-if="searched && !hits.length" class="mf-none">Nothing matches "{{ query }}".</p>
    <div v-for="h in hits" :key="h.mod + '/' + h.field.id" class="mf-hit">
      <div class="mf-where">{{ h.modTitle }} &rsaquo; {{ h.tabTitle }}<span v-if="h.field.group"> &rsaquo; {{ h.field.group }}</span></div>
      <SettingRow :mod="h.mod" :field="h.field" @toast="toast" />
    </div>
    <div v-if="toastText" class="mf-toast">{{ toastText }}</div>
  </div>
</template>

<script setup>
import { ref } from "vue"
import { call } from "./settingsApi.js"
import SettingRow from "./SettingRow.vue"

const query = ref("")
const hits = ref([])
const searched = ref(false)
const toastText = ref("")
let timer, toastTimer

function search() {
  clearTimeout(timer)
  timer = setTimeout(async () => {
    if (!query.value.trim()) { hits.value = []; searched.value = false; return }
    hits.value = (await call("search", query.value)) || []
    searched.value = true
  }, 200)
}

function toast(text) {
  if (!text) return
  toastText.value = text
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => (toastText.value = ""), 3500)
}
</script>

<style lang="scss" scoped>
.mf { padding: 1rem 1.25rem; color: #ece9f1; max-width: 62rem; margin: 0 auto; font-size: 1rem; line-height: 1.4; }
.mf-title { margin: 0 0 0.5rem; font-size: 1.5rem; font-weight: 600; }
.mf-desc { color: #cfcbd8; margin: 0 0 0.75rem; }
.mf-input { width: 100%; box-sizing: border-box; background: #17161b; color: #ece9f1; border: 2px solid #4a4753; border-radius: 0.5rem; padding: 0.6rem 0.8rem; font: inherit; font-size: 1.1rem; }
.mf-input:focus-visible { outline: 3px solid #ffd54f; outline-offset: 2px; }
.mf-none { color: #cfcbd8; margin-top: 1rem; }
.mf-hit { margin-top: 0.75rem; border-top: 1px solid #4a4753; padding-top: 0.5rem; }
.mf-where { font-size: 0.85rem; color: #cfcbd8; padding-left: 0.6rem; }
.mf-toast { position: sticky; bottom: 0.5rem; margin-top: 1rem; padding: 0.6rem 1rem; background: #a8c7fa; color: #062e6f; border-radius: 0.5rem; font-weight: 600; }
</style>
