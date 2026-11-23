<script setup>
/*
  Custom color picker — saturation/value area + hue strip + hex input.
  The native <input type="color"> is NOT used (it would break the design language).
  Output: { id: null, name: t('custom_short'), hex: '#rrggbb', rgb: [r,g,b] }
*/
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { t } from '@/locale'

const props = defineProps({
  modelValue: { type: Object, default: null },
})
const emit = defineEmits(['update:modelValue'])

const hue = ref(174)
const sat = ref(0.75)
const val = ref(1)
const hexInput = ref('69FFEC')

const svArea = ref(null)
const hueBar = ref(null)
let dragging = null

/* ── conversions ────────────────────────────────────────────────── */
function hsvToRgb(h, s, v) {
  const c = v * s
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1))
  const m = v - c
  const seg = Math.floor(h / 60) % 6
  const [r, g, b] = [
    [c, x, 0],
    [x, c, 0],
    [0, c, x],
    [0, x, c],
    [x, 0, c],
    [c, 0, x],
  ][seg]
  return [r + m, g + m, b + m].map((n) => Math.round(n * 255))
}

function rgbToHsv(r, g, b) {
  r /= 255
  g /= 255
  b /= 255
  const max = Math.max(r, g, b)
  const min = Math.min(r, g, b)
  const d = max - min
  let h = 0
  if (d) {
    if (max === r) h = 60 * (((g - b) / d) % 6)
    else if (max === g) h = 60 * ((b - r) / d + 2)
    else h = 60 * ((r - g) / d + 4)
  }
  if (h < 0) h += 360
  return [h, max ? d / max : 0, max]
}

const toHex = (n) => n.toString(16).padStart(2, '0').toUpperCase()

const rgb = computed(() => hsvToRgb(hue.value, sat.value, val.value))
const hex = computed(() => '#' + rgb.value.map(toHex).join(''))
const hueColor = computed(() => `hsl(${hue.value}, 100%, 50%)`)

/* ── notify parent of the change ───────────────────────────────── */
function commit() {
  hexInput.value = hex.value.slice(1)
  emit('update:modelValue', {
    id: null,
    name: t('custom_short'),
    hex: hex.value,
    rgb: [...rgb.value],
  })
}

/** Sync the display when a ready-made color comes in from outside (palette selection). */
watch(
  () => props.modelValue?.hex,
  (v) => {
    if (!v || v.toUpperCase() === hex.value) return
    const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(v)
    if (!m) return
    const [h, s, vv] = rgbToHsv(parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16))
    hue.value = h
    sat.value = s
    val.value = vv
    hexInput.value = v.replace('#', '').toUpperCase()
  },
  { immediate: true },
)

/* ── dragging ───────────────────────────────────────────────────── */
/* A zero-sized rect divides to NaN and the colour becomes '#NaNNaNNaN', which
   sticks until the picker is reopened. It happens whenever a press lands before
   layout has settled — mid-transition, or on a panel that is still collapsed. */
function applySV(e) {
  const r = svArea.value?.getBoundingClientRect()
  if (!r || !r.width || !r.height) return
  sat.value = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width))
  val.value = Math.min(1, Math.max(0, 1 - (e.clientY - r.top) / r.height))
  commit()
}
function applyHue(e) {
  const r = hueBar.value?.getBoundingClientRect()
  if (!r || !r.width) return
  hue.value = Math.min(360, Math.max(0, ((e.clientX - r.left) / r.width) * 360))
  commit()
}
function onMove(e) {
  if (dragging === 'sv') applySV(e)
  else if (dragging === 'hue') applyHue(e)
}
function stop() {
  dragging = null
  window.removeEventListener('mousemove', onMove)
  window.removeEventListener('mouseup', stop)
}
function start(kind, e) {
  dragging = kind
  onMove(e)
  window.addEventListener('mousemove', onMove)
  window.addEventListener('mouseup', stop)
}
onBeforeUnmount(stop)

function onHexInput() {
  const clean = hexInput.value.replace(/[^a-f\d]/gi, '').slice(0, 6)
  hexInput.value = clean.toUpperCase()
  if (clean.length !== 6) return
  const [h, s, v] = rgbToHsv(
    parseInt(clean.slice(0, 2), 16),
    parseInt(clean.slice(2, 4), 16),
    parseInt(clean.slice(4, 6), 16),
  )
  hue.value = h
  sat.value = s
  val.value = v
  commit()
}
</script>

<template>
  <div class="ui-cp">
    <!-- saturation / value -->
    <div
      ref="svArea"
      class="cp-sv"
      :style="{ background: hueColor }"
      @mousedown.prevent="start('sv', $event)"
    >
      <div class="cp-sv-white" />
      <div class="cp-sv-black" />
      <span
        class="cp-dot"
        :style="{ left: sat * 100 + '%', top: (1 - val) * 100 + '%', background: hex }"
      />
    </div>

    <div class="cp-row">
      <span class="cp-preview" :style="{ background: hex }" />

      <div class="cp-controls">
        <div ref="hueBar" class="cp-hue" @mousedown.prevent="start('hue', $event)">
          <span class="cp-hue-thumb" :style="{ left: (hue / 360) * 100 + '%', background: hueColor }" />
        </div>
        <div class="cp-hex">
          <span>#</span>
          <input v-model="hexInput" maxlength="6" spellcheck="false" @input="onHexInput" />
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.ui-cp {
  display: flex;
  flex-direction: column;
  gap: 10px;
  width: 100%;
}
.cp-sv {
  position: relative;
  height: 92px;
  border-radius: var(--r-sm);
  border: 1px solid var(--stroke-2);
  overflow: hidden;
  cursor: crosshair;
}
.cp-sv-white,
.cp-sv-black {
  position: absolute;
  inset: 0;
}
.cp-sv-white {
  background: linear-gradient(to right, var(--text-1), transparent);
}
.cp-sv-black {
  background: linear-gradient(to top, #000, transparent);
}
.cp-dot {
  position: absolute;
  width: 13px;
  height: 13px;
  border-radius: 50%;
  border: 2px solid var(--text-1);
  box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.45);
  transform: translate(-50%, -50%);
  pointer-events: none;
}
.cp-row {
  display: flex;
  align-items: center;
  gap: 10px;
}
.cp-preview {
  width: 38px;
  height: 38px;
  flex-shrink: 0;
  border-radius: var(--r-sm);
  border: 1px solid var(--stroke-2);
}
.cp-controls {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.cp-hue {
  position: relative;
  height: 8px;
  border-radius: var(--r-badge);
  cursor: pointer;
  background: linear-gradient(
    to right,
    #f00 0%,
    #ff0 17%,
    #0f0 33%,
    #0ff 50%,
    #00f 67%,
    #f0f 83%,
    #f00 100%
  );
}
.cp-hue-thumb {
  position: absolute;
  top: 50%;
  width: 14px;
  height: 14px;
  border-radius: 50%;
  border: 2px solid var(--text-1);
  box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.45);
  transform: translate(-50%, -50%);
  pointer-events: none;
}
.cp-hex {
  display: flex;
  align-items: center;
  gap: 4px;
  height: 26px;
  padding: 0 10px;
  border-radius: var(--r-field);
  background: var(--surface-3);
  border: 1px solid var(--stroke-1);
  font-size: 11.5px;
  color: var(--text-4);
  transition: border-color 0.15s;
}
.cp-hex:focus-within {
  border-color: var(--accent);
}
.cp-hex input {
  flex: 1;
  min-width: 0;
  font-size: 11.5px;
  letter-spacing: 0.06em;
  color: var(--text-1);
  font-variant-numeric: tabular-nums;
}
</style>
