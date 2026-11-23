<script setup>
// Custom dropdown (no native <select>, aty-ui). Keyboard: Enter/Space opens, Esc closes, arrows move.
import { computed, onBeforeUnmount, ref } from 'vue'

const props = defineProps({
  modelValue: { default: null },
  options: { type: Array, default: () => [] }, // [{ value, label }]
  placeholder: { type: String, default: '' },
  up: { type: Boolean, default: false },
})
const emit = defineEmits(['update:modelValue'])

const open = ref(false)
const root = ref(null)
const current = computed(() => props.options.find((o) => o.value === props.modelValue))

function pick(o) {
  emit('update:modelValue', o.value)
  open.value = false
}
function onDoc(e) {
  if (root.value && !root.value.contains(e.target)) open.value = false
}
function toggle() {
  open.value = !open.value
  if (open.value) document.addEventListener('mousedown', onDoc)
  else document.removeEventListener('mousedown', onDoc)
}
function onKey(e) {
  if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); toggle() }
  else if (e.key === 'Escape') { open.value = false }
  else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    e.preventDefault()
    const i = props.options.findIndex((o) => o.value === props.modelValue)
    const n = props.options[(i + (e.key === 'ArrowDown' ? 1 : -1) + props.options.length) % props.options.length]
    if (n) emit('update:modelValue', n.value)
  }
}
onBeforeUnmount(() => document.removeEventListener('mousedown', onDoc))
</script>

<template>
  <div ref="root" class="sel-wrap">
    <div class="sel-btn" tabindex="0" role="combobox" :aria-expanded="open" @click="toggle" @keydown="onKey">
      <span :style="{ color: current ? 'var(--text-1)' : 'var(--text-4)' }">{{ current ? current.label : placeholder }}</span>
      <span style="color: var(--text-4)">&#9662;</span>
    </div>
    <div v-if="open" class="sel-menu" :class="{ up }" role="listbox">
      <div v-for="o in options" :key="String(o.value)" class="sel-opt" :class="{ on: o.value === modelValue }" role="option" @click="pick(o)">
        {{ o.label }}
      </div>
    </div>
  </div>
</template>
