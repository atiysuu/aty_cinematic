<script setup>
// Ready-made camera moves, scene set-ups and atmospheres.
// Layout: everything on offer is a compact tile in the list above; the one thing that is picked
// lives in the footer below (what it does, its few settings, the one button). The footer never
// scrolls away, so the action is always in the same place.
// The lists come from Lua (setup payload); names and descriptions are in the locale tables.
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue'
import { useSession } from '@/stores/session'
import { useProject } from '@/stores/project'
import { useUi } from '@/stores/ui'
import { fetchNui } from '@/utils/nui'
import { t } from '@/locale'
import UiSlider from './ui/UiSlider.vue'
import UiSelect from './ui/UiSelect.vue'

const session = useSession()
const project = useProject()
const ui = useUi()

const EMPTY = { moves: [], moveGroups: [], looks: [], lookGroups: [], scenes: [], sceneGroups: [] }
const presets = computed(() => session.config.presets || EMPTY)
const tabs = ['moves', 'scenes', 'looks']
const inGroup = (list, g) => list.filter((x) => x.group === g)

// What a move turns around / the focus goes to: an actor, or whatever the camera looks at.
const targetOptions = computed(() => [
  { value: '', label: t('pr_target_view') },
  ...project.actors.map((a) => ({ value: a.id, label: a.name })),
])
const target = computed(() => (project.actors.some((a) => a.id === ui.presetTarget) ? ui.presetTarget : ''))

const busy = ref(false)

// camera moves ---------------------------------------------------------------------------------
const moveParams = reactive({})
watch(() => presets.value.moves, (list) => {
  list.forEach((m) => { if (!moveParams[m.id]) moveParams[m.id] = { dur: m.dur, amount: m.amt.def, dir: 1, soft: true, shake: true } })
}, { immediate: true })
const selMove = computed(() => presets.value.moves.find((m) => m.id === ui.presetMove) || presets.value.moves[0] || null)
const mp = computed(() => (selMove.value ? moveParams[selMove.value.id] : null))
const moveMode = ref('new')
const moveNote = ref('')
const canAppend = computed(() => !!(project.shot && project.shot.keys.length))
const fmtAmount = (v) => {
  const unit = selMove.value ? selMove.value.amt.unit : 'x'
  if (unit === 'deg') return v.toFixed(0) + '°'
  if (unit === 'pct') return '%' + v.toFixed(0)
  return v.toFixed(1) + '×'
}
const dirLabels = { side: ['pr_left', 'pr_right'], inout: ['pr_out', 'pr_in'], updown: ['pr_down', 'pr_up'] }
function pickMove(m) {
  ui.presetMove = m.id
  moveNote.value = ''
}
async function applyMove() {
  const m = selMove.value, p = mp.value
  if (busy.value || !m || !p) return
  busy.value = true
  const res = await fetchNui('moveApply', {
    id: m.id, dur: p.dur, amount: p.amount, dir: p.dir, soft: p.soft, shake: p.shake,
    mode: canAppend.value ? moveMode.value : 'new', target: target.value || undefined, name: t('mv_' + m.id),
  })
  busy.value = false
  moveNote.value = res.ok ? t('pr_move_done', res.keys) : t('pr_failed')
  if (res.ok) ui.selKeyId = null
}

// scenes ---------------------------------------------------------------------------------------
const selScene = computed(() => presets.value.scenes.find((s) => s.id === ui.presetScene) || presets.value.scenes[0] || null)
const sceneOpt = reactive({ lights: true, look: false, clear: false })
const sceneNote = ref('')
const sceneSub = (s) => [s.peds && t('sc_peds', s.peds), s.vehicles && t('sc_vehicles', s.vehicles), s.lights && t('sc_lightsn', s.lights)].filter(Boolean).join(' · ')
function pickScene(s) {
  ui.presetScene = s.id
  sceneNote.value = ''
}
async function placeScene() {
  const s = selScene.value
  if (busy.value || !s) return
  busy.value = true
  const res = await fetchNui('sceneApply', { id: s.id, lights: sceneOpt.lights, look: sceneOpt.look, clear: sceneOpt.clear })
  busy.value = false
  sceneNote.value = ''
  if (!res.ok) return
  if (res.main) { ui.selectActors([res.main]); ui.presetTarget = res.main }
  if (sceneOpt.look && s.look) ui.lastLook = s.look
}
// Placed scenes are part of the project (they are still listed after closing and reopening):
// each one can be filmed or removed as a whole. The same preset placed twice gets a number.
const placed = computed(() => {
  const seen = {}
  return ((project.doc && project.doc.scenes) || []).map((s) => {
    seen[s.preset] = (seen[s.preset] || 0) + 1
    const def = presets.value.scenes.find((x) => x.id === s.preset)
    return { id: s.id, label: t('sc_' + s.preset) + (seen[s.preset] > 1 ? ' ' + seen[s.preset] : ''), hasCam: !!(def && def.move) }
  })
})
const stageCount = computed(() => project.actors.length + project.lights.length)
async function removeScene(p) {
  if (busy.value) return
  busy.value = true
  await fetchNui('sceneRemove', { id: p.id })
  busy.value = false
  sceneNote.value = ''
}
// The scene's own camera: Lua builds it in front of the scene, wherever the user's camera is now.
async function sceneCamera(p) {
  if (busy.value) return
  busy.value = true
  const res = await fetchNui('sceneMove', { scene: p.id, name: p.label })
  busy.value = false
  sceneNote.value = res.ok ? t('pr_move_done', res.keys) : t('pr_failed')
  if (res.ok) ui.selKeyId = null
}
// "Remove everything" takes two clicks (the second within 4 s): it also removes what was placed by hand.
const confirmClear = ref(false)
let clearTimer = null
async function clearStage() {
  clearTimeout(clearTimer)
  if (!confirmClear.value) {
    confirmClear.value = true
    clearTimer = setTimeout(() => { confirmClear.value = false }, 4000)
    return
  }
  confirmClear.value = false
  await fetchNui('stageClear')
  sceneNote.value = ''
}
onBeforeUnmount(() => clearTimeout(clearTimer))

// atmospheres ----------------------------------------------------------------------------------
const lookOpt = reactive({ dof: false, shake: false })
const hhmm = (m) => String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(Math.round(m % 60)).padStart(2, '0')
const lookLine = (l) => [l.weather || null, l.tod !== false ? hhmm(l.tod) : null, l.filter || null].filter(Boolean).join(' · ') || t('lk_no_filter')
const swatch = (l) => ({ background: `linear-gradient(135deg, #${l.sw[0]}, #${l.sw[1]})` })
const curLook = computed(() => presets.value.looks.find((l) => l.id === ui.lastLook) || null)
async function applyLook(l) {
  if (busy.value) return
  busy.value = true
  const res = await fetchNui('lookApply', { id: l.id, dof: lookOpt.dof && l.dof, shake: lookOpt.shake && l.shake, target: target.value || undefined })
  busy.value = false
  if (res.ok) ui.lastLook = l.id
}
</script>

<template>
  <div class="p-fixed">
    <div class="pill-group" role="tablist">
      <button v-for="tab in tabs" :key="tab" :class="{ on: ui.presetTab === tab }" role="tab" @click="ui.presetTab = tab">{{ t('pr_tab_' + tab) }}</button>
    </div>

    <!-- camera moves -->
    <template v-if="ui.presetTab === 'moves'">
      <div class="p-scroll">
        <template v-for="g in presets.moveGroups" :key="g">
          <span class="grp">{{ t('mvg_' + g) }}</span>
          <div class="tile-grid">
            <button v-for="m in inGroup(presets.moves, g)" :key="m.id" class="tile" :class="{ sel: selMove && selMove.id === m.id }" @click="pickMove(m)">{{ t('mv_' + m.id) }}</button>
          </div>
        </template>
      </div>
      <div v-if="selMove && mp" class="p-foot">
        <div class="foot-head"><span class="t">{{ t('mv_' + selMove.id) }}</span><span class="d">{{ t('mvd_' + selMove.id) }}</span></div>
        <div class="field-row">
          <span class="field-label">{{ t('pr_target') }}</span>
          <UiSelect class="grow" up :model-value="target" :options="targetOptions" @update:model-value="(v) => (ui.presetTarget = v)" />
        </div>
        <div class="row">
          <UiSlider v-model="mp.dur" class="grow" :min="1" :max="30" :step="0.5" :label="t('pr_duration')" :display="(v) => v.toFixed(1) + ' s'" />
          <UiSlider v-model="mp.amount" class="grow" :min="selMove.amt.min" :max="selMove.amt.max" :step="selMove.amt.step" :label="t('pr_amount_' + selMove.amt.unit)" :display="fmtAmount" />
        </div>
        <div v-if="selMove.dir || canAppend" class="row">
          <div v-if="selMove.dir" class="pill-group grow">
            <button :class="{ on: mp.dir === -1 }" @click="mp.dir = -1">{{ t(dirLabels[selMove.dir][0]) }}</button>
            <button :class="{ on: mp.dir === 1 }" @click="mp.dir = 1">{{ t(dirLabels[selMove.dir][1]) }}</button>
          </div>
          <div v-if="canAppend" class="pill-group grow">
            <button :class="{ on: moveMode === 'new' }" @click="moveMode = 'new'">{{ t('pr_mode_new') }}</button>
            <button :class="{ on: moveMode === 'append' }" @click="moveMode = 'append'">{{ t('pr_mode_append') }}</button>
          </div>
        </div>
        <div class="row wrap">
          <button class="opt" :class="{ on: mp.soft }" :aria-pressed="mp.soft" @click="mp.soft = !mp.soft">{{ t('pr_soft') }}</button>
          <button v-if="selMove.shake" class="opt" :class="{ on: mp.shake }" :aria-pressed="mp.shake" @click="mp.shake = !mp.shake">{{ t('pr_shake_short') }}</button>
        </div>
        <button class="ui-btn accent" :disabled="busy || !project.doc" @click="applyMove">{{ t('pr_apply') }}</button>
        <span v-if="moveNote" class="mini note">{{ moveNote }}</span>
      </div>
    </template>

    <!-- scene set-ups -->
    <template v-else-if="ui.presetTab === 'scenes'">
      <div class="p-scroll">
        <template v-for="g in presets.sceneGroups" :key="g">
          <span class="grp">{{ t('scg_' + g) }}</span>
          <div class="tile-grid">
            <button v-for="s in inGroup(presets.scenes, g)" :key="s.id" class="tile" :class="{ sel: selScene && selScene.id === s.id }" @click="pickScene(s)">
              <span>{{ t('sc_' + s.id) }}</span>
              <span class="sub">{{ sceneSub(s) }}</span>
            </button>
          </div>
        </template>
      </div>
      <div v-if="selScene" class="p-foot">
        <div class="foot-head"><span class="t">{{ t('sc_' + selScene.id) }}</span><span class="d">{{ t('scd_' + selScene.id) }}</span></div>
        <div class="row wrap">
          <button class="opt" :class="{ on: sceneOpt.lights }" :aria-pressed="sceneOpt.lights" @click="sceneOpt.lights = !sceneOpt.lights">{{ t('sc_lights_short') }}</button>
          <button v-if="selScene.look" class="opt" :class="{ on: sceneOpt.look }" :aria-pressed="sceneOpt.look" @click="sceneOpt.look = !sceneOpt.look">{{ t('sc_look_short') }}: {{ t('lk_' + selScene.look) }}</button>
          <button class="opt" :class="{ on: sceneOpt.clear }" :aria-pressed="sceneOpt.clear" @click="sceneOpt.clear = !sceneOpt.clear">{{ t('sc_clear_short') }}</button>
        </div>
        <button class="ui-btn accent" :disabled="busy || !project.doc" @click="placeScene">{{ t('sc_place') }}</button>
        <template v-if="placed.length || stageCount">
          <div class="foot-sep" />
          <template v-if="placed.length">
            <span class="mini">{{ t('sc_placed_list') }}</span>
            <div class="placed">
              <div v-for="p in placed" :key="p.id" class="placed-row">
                <span class="t">{{ p.label }}</span>
                <button v-if="p.hasCam" class="ui-btn small accent" :disabled="busy" @click="sceneCamera(p)">{{ t('sc_cam_short') }}</button>
                <button class="ui-btn small ghost" :disabled="busy" @click="removeScene(p)">{{ t('sc_remove') }}</button>
              </div>
            </div>
          </template>
          <button v-if="stageCount" class="ui-btn small" :class="confirmClear ? 'danger' : 'ghost'" :disabled="busy" @click="clearStage">
            {{ confirmClear ? t('sc_clear_confirm', project.actors.length, project.lights.length) : t('sc_clear_all') }}
          </button>
          <span v-if="sceneNote" class="mini note">{{ sceneNote }}</span>
        </template>
      </div>
    </template>

    <!-- atmospheres -->
    <template v-else>
      <div class="p-scroll">
        <template v-for="g in presets.lookGroups" :key="g">
          <span class="grp">{{ t('lkg_' + g) }}</span>
          <div class="tile-grid">
            <button v-for="l in inGroup(presets.looks, g)" :key="l.id" class="tile look" :class="{ sel: ui.lastLook === l.id }" :disabled="busy" @click="applyLook(l)">
              <i class="sw" :style="swatch(l)" /><span>{{ t('lk_' + l.id) }}</span>
            </button>
          </div>
        </template>
      </div>
      <div class="p-foot">
        <div class="foot-head">
          <span class="t">{{ curLook ? t('lk_' + curLook.id) : t('pr_tab_looks') }}</span>
          <span class="d">{{ curLook ? lookLine(curLook) : t('lk_pick') }}</span>
        </div>
        <div class="row wrap">
          <button class="opt" :class="{ on: lookOpt.dof }" :aria-pressed="lookOpt.dof" @click="lookOpt.dof = !lookOpt.dof">{{ t('lk_dof_short') }}</button>
          <button class="opt" :class="{ on: lookOpt.shake }" :aria-pressed="lookOpt.shake" @click="lookOpt.shake = !lookOpt.shake">{{ t('lk_shake_short') }}</button>
        </div>
        <div v-if="lookOpt.dof" class="field-row">
          <span class="field-label">{{ t('pr_target') }}</span>
          <UiSelect class="grow" up :model-value="target" :options="targetOptions" @update:model-value="(v) => (ui.presetTarget = v)" />
        </div>
      </div>
    </template>
  </div>
</template>
