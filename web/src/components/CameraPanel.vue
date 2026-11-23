<script setup>
import { computed } from 'vue'
import { useSession } from '@/stores/session'
import { useProject } from '@/stores/project'
import { useUi } from '@/stores/ui'
import { fetchNui, sendThrottled } from '@/utils/nui'
import { t } from '@/locale'
import UiSlider from './ui/UiSlider.vue'
import UiToggle from './ui/UiToggle.vue'
import UiSelect from './ui/UiSelect.vue'

const session = useSession()
const project = useProject()
const ui = useUi()

const cfg = computed(() => session.config)
const cam = computed(() => session.cam)
const dof = computed(() => session.cam.dof || {})
const fmt = (v) => (Number.isFinite(v) ? v.toFixed(2) : '-')

const focusOptions = computed(() => [
  { value: '', label: t('dof_manual') },
  ...project.actors.map((a) => ({ value: a.id, label: a.name })),
])

const hold = (f) => { session.camHold[f] = performance.now() + 500 }
function camSet(patch, key) {
  sendThrottled('cam_' + key, 'camSet', patch)
}
function setDof(field, value) {
  // optimistic echo so the slider does not jump back while Lua confirms
  hold('dof')
  session.cam = { ...session.cam, dof: { ...session.cam.dof, [field]: value } }
  camSet({ dof: { [field]: value } }, 'dof_' + field)
}
function setFocus(v) {
  session.cam = { ...session.cam, dof: { ...session.cam.dof, target: v || null } }
  fetchNui('camSet', { dof: { target: v || false } })
}
function setSpeed(v) { hold('speed'); session.cam = { ...session.cam, speed: v }; camSet({ speed: v }, 'speed') }
function setFov(v) { hold('fov'); session.cam = { ...session.cam, fov: v }; camSet({ fov: v }, 'fov') }
function setSmooth(v) { session.state.smoothing = v; camSet({ smoothing: v }, 'smooth') }
const orbit = computed(() => (session.state.rig === 'orbit' && session.cam.orbit) || null)
function setOrbit(field, v) {
  hold('orbit')
  session.cam = { ...session.cam, orbit: { ...(session.cam.orbit || {}), [field]: v } }
  sendThrottled('orbit_' + field, 'orbitSet', { [field]: v })
}
function setPathViz(v) { session.state.pathViz = v; fetchNui('camSet', { pathViz: v }) }
function setInertia(v) { session.state.inertia = v; camSet({ inertia: v }, 'inertia') }
// Camera shake: per shot, saved with the project.
const shakePresets = ['none', 'handheld', 'walk', 'run', 'vehicle', 'action', 'drone']
const shake = computed(() => (project.shot && project.shot.shake) || null)
// keys with their own shake override this default during playback: say so, offer to clear them
const ownShakeKeys = computed(() => (project.shot ? project.shot.keys.filter((k) => k.shake).length : 0))
function clearKeyShakes() {
  const s = project.shot
  if (!s) return
  project.markEdit()
  s.keys.forEach((k) => { k.shake = undefined })
  fetchNui('keysClearShake', { shotId: s.id })
}
function setShake(field, value) {
  const s = project.shot
  if (!s) return
  project.markEdit()
  s.shake = { ...(s.shake || {}), [field]: value }
  sendThrottled('shake_' + field, 'shotUpdate', { id: s.id, patch: { shake: { [field]: value } } })
}
function setRec(field, v) {
  project.markEdit()
  if (project.doc) project.doc.settings[field] = v
  if (typeof v === 'boolean') fetchNui('settingsSet', { [field]: v })
  else sendThrottled('rec_' + field, 'settingsSet', { [field]: v })
}
</script>

<template>
  <div class="p-body">
    <div class="blk">
      <div class="blk-head">{{ t('movement') }}</div>
      <UiSlider :model-value="cam.speed" :min="cfg.speed.min" :max="cfg.speed.max" :step="0.05" :label="t('speed')" @update:model-value="setSpeed" />
      <UiSlider :model-value="cam.fov" :min="cfg.fov.min" :max="cfg.fov.max" :step="0.5" :label="t('fov')" @update:model-value="setFov" />
      <UiSlider :model-value="session.state.inertia" :min="0" :max="1" :step="0.05" :label="t('inertia')" @update:model-value="setInertia" />
      <UiSlider :model-value="session.state.smoothing" :min="0" :max="1" :step="0.05" :label="t('smoothing')" @update:model-value="setSmooth" />
      <span class="mini">{{ t('movement_hint') }}</span>
      <button class="ui-btn small ghost" @click="fetchNui('camSet', { resetRoll: true })">{{ t('reset_roll') }}</button>
    </div>

    <div v-if="orbit" class="blk">
      <div class="blk-head">{{ t('orbit') }}</div>
      <UiSlider :model-value="orbit.dist" :min="0.5" :max="80" :step="0.1" :label="t('orbit_radius')" :display="(v) => v.toFixed(1) + ' m'" @update:model-value="(v) => setOrbit('dist', v)" />
      <UiSlider :model-value="orbit.lift" :min="-10" :max="40" :step="0.1" :label="t('orbit_lift')" :display="(v) => v.toFixed(1) + ' m'" @update:model-value="(v) => setOrbit('lift', v)" />
      <UiSlider :model-value="orbit.spin" :min="-120" :max="120" :step="1" :label="t('orbit_spin')" :display="(v) => (v === 0 ? t('off') : v.toFixed(0) + ' deg/s')" @update:model-value="(v) => setOrbit('spin', v)" />
      <span class="mini">{{ t('orbit_hint') }}</span>
    </div>

    <div class="blk">
      <div class="blk-head">{{ t('shake') }}</div>
      <template v-if="shake">
        <div class="pill-group pill-grid">
          <button v-for="p in shakePresets" :key="p" :class="{ on: shake.preset === p }" @click="setShake('preset', p)">{{ t('shake_' + p) }}</button>
        </div>
        <UiSlider v-if="shake.preset !== 'none'" :model-value="shake.amount" :min="0" :max="3" :step="0.05" :label="t('shake_amount')" @update:model-value="(v) => setShake('amount', v)" />
        <UiSlider :model-value="shake.speed" :min="0" :max="1" :step="0.05" :label="t('shake_speed')" @update:model-value="(v) => setShake('speed', v)" />
        <UiSlider :model-value="shake.whip" :min="0" :max="1" :step="0.05" :label="t('shake_whip')" @update:model-value="(v) => setShake('whip', v)" />
        <div v-if="ownShakeKeys" class="warn-box">
          <span class="mini">{{ t('shake_keys_override', ownShakeKeys) }}</span>
          <button class="ui-btn small ghost" @click="clearKeyShakes">{{ t('shake_keys_clear') }}</button>
        </div>
        <span class="mini">{{ t('shake_note') }}</span>
      </template>
      <span v-else class="mini">{{ t('shake_need_shot') }}</span>
    </div>

    <div v-if="cfg.dof.enabled" class="blk">
      <div class="blk-head">{{ t('dof') }}</div>
      <UiToggle :model-value="!!dof.on" :label="t('dof_on')" @update:model-value="(v) => setDof('on', v)" />
      <template v-if="dof.on">
        <UiSlider :model-value="dof.near ?? 0.5" :min="0" :max="100" :step="0.1" :label="t('dof_near')" @update:model-value="(v) => setDof('near', v)" />
        <UiSlider :model-value="dof.far ?? 12" :min="0" :max="500" :step="0.5" :label="t('dof_far')" @update:model-value="(v) => setDof('far', v)" />
        <UiSlider :model-value="dof.str ?? 1" :min="0" :max="1" :step="0.05" :label="t('dof_strength')" @update:model-value="(v) => setDof('str', v)" />
        <div>
          <span class="field-label">{{ t('dof_focus') }}</span>
          <UiSelect :model-value="dof.target || ''" :options="focusOptions" @update:model-value="setFocus" />
        </div>
      </template>
    </div>

    <div class="blk">
      <div class="blk-head">{{ t('output') }}</div>
      <UiToggle :model-value="session.state.pathViz === true" :label="t('path_viz')" @update:model-value="setPathViz" />
      <button class="ui-btn small ghost" @click="ui.panel = 'framing'">{{ t('open_framing') }}</button>
    </div>

    <div v-if="project.doc" class="blk">
      <div class="blk-head">{{ t('rec') }}</div>
      <UiToggle :model-value="project.doc.settings.recSingle !== false" :label="t('rec_single')" @update:model-value="(v) => setRec('recSingle', v)" />
      <UiSlider :model-value="project.doc.settings.leadIn ?? 4" :min="0" :max="10" :step="0.1" :label="t('rec_leadin')" :display="(v) => v.toFixed(1) + ' s'" @update:model-value="(v) => setRec('leadIn', v)" />
      <UiSlider :model-value="project.doc.settings.tail ?? 1" :min="0" :max="10" :step="0.1" :label="t('rec_tail')" :display="(v) => v.toFixed(1) + ' s'" @update:model-value="(v) => setRec('tail', v)" />
      <span class="mini">{{ t('rec_note') }}</span>
    </div>

    <div class="blk">
      <div class="blk-head">{{ t('readout') }}</div>
      <div class="row"><span class="mini grow">{{ t('pos') }}</span><span class="val">{{ fmt(cam.pos[0]) }} {{ fmt(cam.pos[1]) }} {{ fmt(cam.pos[2]) }}</span></div>
      <div class="row"><span class="mini grow">{{ t('rot') }}</span><span class="val">{{ fmt(cam.rot[0]) }} {{ fmt(cam.rot[1]) }} {{ fmt(cam.rot[2]) }}</span></div>
    </div>
  </div>
</template>
