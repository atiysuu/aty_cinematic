<script setup>
// Two draggable control handles of a CSS-style cubic-bezier(x1, y1, x2, y2).
import { computed, ref } from 'vue'

const props = defineProps({ modelValue: { type: Array, default: () => [0.42, 0, 0.58, 1] } })
const emit = defineEmits(['update:modelValue', 'change'])

const W = 240
const H = 130
const PAD = 14
const svg = ref(null)
let drag = -1

const bez = computed(() => (props.modelValue && props.modelValue.length === 4 ? props.modelValue : [0.42, 0, 0.58, 1]))
const px = (x) => PAD + x * (W - 2 * PAD)
const py = (y) => H - PAD - ((y + 0.5) / 2) * (H - 2 * PAD) // y range -0.5 .. 1.5 shown
const p0 = computed(() => [px(0), py(0)])
const p3 = computed(() => [px(1), py(1)])
const h1 = computed(() => [px(bez.value[0]), py(bez.value[1])])
const h2 = computed(() => [px(bez.value[2]), py(bez.value[3])])
const path = computed(() => `M${p0.value[0]},${p0.value[1]} C${h1.value[0]},${h1.value[1]} ${h2.value[0]},${h2.value[1]} ${p3.value[0]},${p3.value[1]}`)

function fromEvent(e) {
  const r = svg.value.getBoundingClientRect()
  const sx = ((e.clientX - r.left) / r.width) * W
  const sy = ((e.clientY - r.top) / r.height) * H
  const x = Math.min(1, Math.max(0, (sx - PAD) / (W - 2 * PAD)))
  const y = Math.min(1.5, Math.max(-0.5, ((H - PAD - sy) / (H - 2 * PAD)) * 2 - 0.5))
  return [Number(x.toFixed(3)), Number(y.toFixed(3))]
}
function down(i, e) {
  drag = i
  e.target.setPointerCapture(e.pointerId)
}
function move(e) {
  if (drag < 0) return
  const [x, y] = fromEvent(e)
  const next = [...bez.value]
  if (drag === 0) { next[0] = x; next[1] = y } else { next[2] = x; next[3] = y }
  emit('update:modelValue', next)
}
function up() {
  if (drag >= 0) emit('change', [...bez.value])
  drag = -1
}
</script>

<template>
  <svg ref="svg" class="bez" :viewBox="`0 0 ${W} ${H}`" @pointermove="move" @pointerup="up" @pointercancel="up">
    <line :x1="p0[0]" :y1="p0[1]" :x2="h1[0]" :y2="h1[1]" stroke="rgba(255,255,255,.25)" />
    <line :x1="p3[0]" :y1="p3[1]" :x2="h2[0]" :y2="h2[1]" stroke="rgba(255,255,255,.25)" />
    <path :d="path" fill="none" stroke="var(--accent)" stroke-width="2" />
    <circle :cx="p0[0]" :cy="p0[1]" r="3" fill="#fff" />
    <circle :cx="p3[0]" :cy="p3[1]" r="3" fill="#fff" />
    <circle :cx="h1[0]" :cy="h1[1]" r="6" fill="var(--accent)" style="cursor: grab" @pointerdown="down(0, $event)" />
    <circle :cx="h2[0]" :cy="h2[1]" r="6" fill="var(--accent)" style="cursor: grab" @pointerdown="down(1, $event)" />
  </svg>
</template>
