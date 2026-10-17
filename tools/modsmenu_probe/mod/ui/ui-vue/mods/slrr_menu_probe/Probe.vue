<template>
  <div class="probe">
    <h3>Mods menu probe</h3>
    <p>If you can read this, a mod can put a card into the pause menu.</p>
    <BngButton @click="count++">Clicked {{ count }} times</BngButton>
  </div>
</template>

<script setup>
import { ref } from "vue"
import { BngButton } from "@/common/components/base"
const count = ref(0)
</script>

<style lang="scss" scoped>
.probe { padding: 1em; }
</style>
