<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useSession } from '@/stores/session'
import { useProject } from '@/stores/project'
import { useUi } from '@/stores/ui'
import { fetchNui, sendThrottled } from '@/utils/nui'
import { t } from '@/locale'
import Icon from './ui/Icon.vue'

const session = useSession()
const project = useProject()
const ui = useUi()

const scroller = ref(null)
const canvas = ref(null)
const editingShot = ref(null)
const editName = ref('')

const shot = computed(() => project.shot)
const keys = computed(() => (shot.value ? shot.value.keys : []))
const envKeys = computed(() => keys.value.filter((k) => k.env && Object.keys(k.env).length))
const px = computed(() => ui.pxPerSec)
const width = computed(() => Math.max(600, (project.duration + 12) * px.value))
const playing = computed(() => session.state.playing || session.state.preloading)

// playhead (a drag keeps its own value so the echo from Lua cannot fight the pointer)
const dragHead = ref(null)
const headT = computed(() => (dragHead.value !== null ? dragHead.value : session.playhead.t))

const step = computed(() => (px.value >= 80 ? 1 : px.value >= 35 ? 2 : px.value >= 18 ? 5 : 10))
const ticks = computed(() => {
  const out = []
  const total = Math.ceil(width.value / px.value)
  for (let s = 0; s <= total; s += step.value) out.push(s)
  return out
})
const fmtTime = (v) => {
  const m = Math.floor(v / 60)
  return String(m).padStart(2, '0') + ':' + (v - m * 60).toFixed(2).padStart(5, '0')
}

function tFromEvent(e) {
  const r = canvas.value.getBoundingClientRect()
  return Math.max(0, Math.round(((e.clientX - r.left) / px.value) * 20) / 20)
}

// scrub
function rulerDown(e) {
  if (!shot.value) return
  e.currentTarget.setPointerCapture(e.pointerId)
  dragHead.value = tFromEvent(e)
  sendThrottled('scrub', 'scrub', { t: dragHead.value }, 33)
}
function rulerMove(e) {
  if (dragHead.value === null) return
  dragHead.value = tFromEvent(e)
  sendThrottled('scrub', 'scrub', { t: dragHead.value }, 33)
}
function rulerUp() {
  if (dragHead.value === null) return
  fetchNui('scrub', { t: dragHead.value })
  dragHead.value = null
}

// key drag
let drag = null
function keyDown(k, e) {
  ui.selKeyId = k.id
  e.currentTarget.setPointerCapture(e.pointerId)
  drag = { id: k.id, moved: false }
}
function keyMove(k, e) {
  if (!drag || drag.id !== k.id) return
  const nt = Math.round(tFromEvent(e) * 10) / 10 // snap 0.1 s
  if (nt === k.t) return
  drag.moved = true
  project.markEdit()
  k.t = nt
  sendThrottled('keydrag_' + k.id, 'keyUpdate', { shotId: shot.value.id, keyId: k.id, patch: { t: nt } })
}
function keyUp() {
  // a click (no drag) jumps the playhead and the camera to that key
  if (drag && !drag.moved && shot.value) fetchNui('keyGoto', { shotId: shot.value.id, keyId: drag.id })
  drag = null
}

// transport
function togglePlay() {
  if (!shot.value) return
  if (playing.value) fetchNui('pause')
  else fetchNui('play', { shotId: shot.value.id, from: session.state.scrub ? session.playhead.t : 0, loop: shot.value.loop })
}
function addKey() {
  if (!shot.value) return
  fetchNui('keyAdd', { shotId: shot.value.id, t: session.playhead.t })
}

// Delete / Backspace-free removal of the selected key (ignored while typing in a field)
function onKeydown(e) {
  if (e.key !== 'Delete' || !shot.value || !ui.selKeyId) return
  const tag = e.target && e.target.tagName
  if (tag === 'INPUT' || tag === 'TEXTAREA' || (e.target && e.target.isContentEditable)) return
  e.preventDefault()
  fetchNui('keyDelete', { shotId: shot.value.id, keyId: ui.selKeyId })
  ui.selKeyId = null
}
onMounted(() => window.addEventListener('keydown', onKeydown))
onBeforeUnmount(() => window.removeEventListener('keydown', onKeydown))
function zoom(f) { ui.pxPerSec = Math.min(300, Math.max(8, ui.pxPerSec * f)) }

// shots
function startRename(s) { editingShot.value = s.id; editName.value = s.name }
function commitRename() {
  if (editingShot.value && editName.value.trim()) fetchNui('shotUpdate', { id: editingShot.value, patch: { name: editName.value.trim() } })
  editingShot.value = null
}
function selectShot(s) {
  ui.selKeyId = null
  fetchNui('shotSelect', { id: s.id })
}
</script>

<template>
  <div class="timeline glass ui-blocking">
    <div class="tl-top">
      <div class="tl-shots">
        <template v-for="s in project.doc ? project.doc.shots : []" :key="s.id">
          <input v-if="editingShot === s.id" v-model="editName" class="cine-input" style="width: 120px; height: 26px" @keydown.enter="commitRename" @keydown.esc="editingShot = null" @blur="commitRename" />
          <button v-else class="shot-tab" :class="{ on: s.id === session.state.shotId }" @click="selectShot(s)" @dblclick="startRename(s)">{{ s.name }}</button>
        </template>
        <button class="ui-icon-btn sm" :disabled="!project.doc" :title="t('shot_add')" @click="fetchNui('shotAdd', {})"><Icon name="plus" :size="10" /></button>
      </div>
      <template v-if="shot">
        <button class="ui-icon-btn sm" :title="t('shot_duplicate')" @click="fetchNui('shotDuplicate', { id: shot.id })"><Icon name="copy" :size="10" /></button>
        <button class="ui-icon-btn sm danger-h" :title="t('shot_delete')" @click="fetchNui('shotDelete', { id: shot.id })"><Icon name="trash" :size="10" /></button>
        <div class="sep" style="width: 1px; height: 18px; background: var(--stroke-2)" />
        <button class="ui-icon-btn" :class="{ on: playing }" :title="t('play')" @click="togglePlay"><Icon :name="playing ? 'pause' : 'play'" /></button>
        <button class="ui-icon-btn" :title="t('stop')" @click="fetchNui('stop')"><Icon name="stop" /></button>
        <button class="ui-icon-btn" :class="{ on: shot.loop }" :title="t('loop')" @click="fetchNui('shotUpdate', { id: shot.id, patch: { loop: !shot.loop } })"><Icon name="loop" /></button>
        <button class="ui-icon-btn accent-h" :title="t('add_key')" @click="addKey"><Icon name="key" /></button>
        <button class="ui-icon-btn rec-btn" :title="t('rec_shot')" :disabled="shot.keys.length < 2" @click="fetchNui('recordShot')"><Icon name="record" /></button>
        <button class="ui-btn small ghost rec-all" :title="t('rec_all_tip')" @click="fetchNui('recordAll')"><Icon name="record" :size="10" />{{ t('rec_all') }}</button>
        <span class="tl-time">{{ fmtTime(headT) }}</span>
        <button class="ui-icon-btn sm" :title="t('zoom_out')" @click="zoom(0.8)">-</button>
        <button class="ui-icon-btn sm" :title="t('zoom_in')" @click="zoom(1.25)">+</button>
      </template>
    </div>

    <div v-if="!shot" class="empty" style="margin: 0 12px 12px">{{ project.doc ? t('no_shots') : t('no_project') }}</div>
    <div v-else ref="scroller" class="tl-scroll">
      <div ref="canvas" class="tl-canvas" :style="{ width: width + 'px' }">
        <div class="tl-ruler" @pointerdown="rulerDown" @pointermove="rulerMove" @pointerup="rulerUp" @pointercancel="rulerUp">
          <div v-for="s in ticks" :key="s" class="tl-tick" :style="{ left: s * px + 'px' }">{{ s }}s</div>
        </div>
        <div class="tl-lane" :style="{ top: '26px' }">
          <span class="tl-lane-label">{{ t('lane_camera') }}</span>
          <template v-for="k in keys" :key="k.id">
            <div v-if="k.hold > 0" class="tl-hold" :style="{ left: k.t * px + 'px', width: k.hold * px + 'px' }" />
            <button class="tl-key" :class="{ sel: k.id === ui.selKeyId, shk: !!k.shake }" :style="{ left: k.t * px + 'px' }" :title="k.t.toFixed(1) + 's'"
              @pointerdown="keyDown(k, $event)" @pointermove="keyMove(k, $event)" @pointerup="keyUp" @pointercancel="keyUp" />
          </template>
        </div>
        <div class="tl-lane" :style="{ top: '62px' }">
          <span class="tl-lane-label">{{ t('lane_env') }}</span>
          <button v-for="k in envKeys" :key="k.id" class="tl-key env" :class="{ sel: k.id === ui.selKeyId }" :style="{ left: k.t * px + 'px' }" :title="k.t.toFixed(1) + 's'" @click="ui.selKeyId = k.id; fetchNui('keyGoto', { shotId: shot.id, keyId: k.id })" />
        </div>
        <div class="tl-head" :style="{ left: headT * px + 'px' }" />
      </div>
    </div>
  </div>
</template>
