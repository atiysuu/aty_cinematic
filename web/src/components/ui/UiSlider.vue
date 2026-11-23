<script setup>
// The native <input type=range> is NOT used — this is drawn with pointer dragging.
import { computed, onBeforeUnmount, ref } from 'vue'

const props = defineProps({
  modelValue: { type: Number, default: 0 },
  min: { type: Number, default: 0 },
  max: { type: Number, default: 100 },
  step: { type: Number, default: 1 },
  label: { type: String, default: '' },
  display: { type: Function, default: null },
})
// `change`: once, when the drag ENDS. Expensive work such as saving should run on release,
// not for every pixel.
const emit = defineEmits(['update:modelValue', 'change'])

const track = ref(null)
const dragging = ref(false)
/* The LAST value during a drag.
   `change` used to emit `props.modelValue`. That is only right when the parent listens to
   `update:modelValue` and feeds the prop back; where it does not, the prop never changes, the
   OLD value was written back on release and the slider looked as if it did nothing. */
const lastValue = ref(null)

const pct = computed(() => {
  const span = props.max - props.min || 1
  return Math.min(100, Math.max(0, ((props.modelValue - props.min) / span) * 100))
})
const shown = computed(() =>
  props.display ? props.display(props.modelValue) : String(props.modelValue),
)

function valueFromEvent(e) {
  const rect = track.value.getBoundingClientRect()
  const ratio = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width))
  const raw = props.min + ratio * (props.max - props.min)
  const snapped = Math.round(raw / props.step) * props.step
  const digits = (String(props.step).split('.')[1] || '').length
  return Number(Math.min(props.max, Math.max(props.min, snapped)).toFixed(digits))
}

function onDown(e) {
  dragging.value = true
  lastValue.value = valueFromEvent(e)
  emit('update:modelValue', lastValue.value)
  window.addEventListener('mousemove', onMove)
  window.addEventListener('mouseup', onUp)
}
function onMove(e) {
  if (!dragging.value) return
  lastValue.value = valueFromEvent(e)
  emit('update:modelValue', lastValue.value)
}
function onUp() {
  const wasDragging = dragging.value
  dragging.value = false
  window.removeEventListener('mousemove', onMove)
  window.removeEventListener('mouseup', onUp)
  if (wasDragging) emit('change', lastValue.value !== null ? lastValue.value : props.modelValue)
  lastValue.value = null
}
function nudge(dir) {
  const v = Math.min(props.max, Math.max(props.min, props.modelValue + dir * props.step))
  emit('update:modelValue', v)
  emit('change', v)
}
onBeforeUnmount(onUp)
</script>

<template>
  <div class="ui-slider">
    <div v-if="label" class="s-head">
      <span class="s-label">{{ label }}</span>
      <span class="s-val">{{ shown }}</span>
    </div>
    <div
      class="s-track-wrap"
      tabindex="0"
      @mousedown="onDown"
      @keydown.left.prevent="nudge(-1)"
      @keydown.right.prevent="nudge(1)"
    >
      <div ref="track" class="s-track">
        <div class="s-fill" :style="{ left: 0, width: pct + '%' }" />
        <div class="s-thumb" :class="{ drag: dragging }" :style="{ left: pct + '%' }" />
      </div>
    </div>
  </div>
</template>
