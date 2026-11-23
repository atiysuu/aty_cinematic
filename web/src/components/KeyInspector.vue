<script setup>
import { computed } from 'vue'
import { useSession } from '@/stores/session'
import { useProject } from '@/stores/project'
import { useUi } from '@/stores/ui'
import { fetchNui, sendThrottled } from '@/utils/nui'
import { t } from '@/locale'
import Icon from './ui/Icon.vue'
import UiSlider from './ui/UiSlider.vue'
import UiToggle from './ui/UiToggle.vue'
import BezierEditor from './BezierEditor.vue'
import EnvFields from './EnvFields.vue'

const session = useSession()
const project = useProject()
const ui = useUi()

const shot = computed(() => project.shot)
const key = computed(() => (shot.value ? shot.value.keys.find((k) => k.id === ui.selKeyId) || null : null))
const index = computed(() => (shot.value && key.value ? shot.value.keys.indexOf(key.value) + 1 : 0))
const maxT = computed(() => Math.max(10, project.duration + 20))
const interps = ['smooth', 'linear', 'hold']
const eases = ['flow', 'linear', 'easeIn', 'easeOut', 'easeInOut', 'bezier']
const applyAll = () => fetchNui('keysApplyMotion', { shotId: shot.value.id, keyId: key.value.id })

// Per-key shake: own setting from this key on (blends in from the previous key), or inherit.
const shakePresets = ['none', 'handheld', 'walk', 'run', 'vehicle', 'action', 'drone']
const SHAKE_DEFAULT = { preset: 'none', amount: 1, speed: 0, whip: 0 }
function toggleShake(on) {
  if (!key.value || !shot.value) return
  project.markEdit()
  if (on) {
    const start = { ...SHAKE_DEFAULT, ...(shot.value.shake || {}) }
    key.value.shake = start
    fetchNui('keyUpdate', { shotId: shot.value.id, keyId: key.value.id, patch: { shake: start } })
  } else {
    key.value.shake = undefined
    fetchNui('keyUpdate', { shotId: shot.value.id, keyId: key.value.id, patch: { shakeClear: true } })
  }
}
function setShake(field, v) {
  if (!key.value || !key.value.shake) return
  const next = { ...key.value.shake, [field]: v }
  patch({ shake: next }, (k) => (k.shake = next))
}

function patch(p, local) {
  if (!key.value || !shot.value) return
  project.markEdit()
  if (local) local(key.value)
  sendThrottled('key_' + key.value.id + Object.keys(p).join(','), 'keyUpdate', { shotId: shot.value.id, keyId: key.value.id, patch: p })
}
const setDof = (f, v) => patch({ dof: { [f]: v } }, (k) => { k.dof[f] = v })
const setEnv = (f, v) => patch({ env: { [f]: v } }, (k) => { k.env = { ...(k.env || {}), [f]: v } })
function clearEnv(f) {
  if (!key.value || !shot.value) return
  project.markEdit()
  const next = { ...(key.value.env || {}) }
  delete next[f]
  key.value.env = Object.keys(next).length ? next : undefined
  fetchNui('keyUpdate', { shotId: shot.value.id, keyId: key.value.id, patch: { envClear: [f] } })
}
function remove() {
  fetchNui('keyDelete', { shotId: shot.value.id, keyId: key.value.id })
  ui.selKeyId = null
}
</script>

<template>
  <div v-if="key" class="inspector glass ui-blocking">
    <div class="p-head">
      <Icon name="key" :size="12" />
      <span style="flex: 1">{{ t('key') }} {{ index }}</span>
      <button class="ui-icon-btn sm" :title="t('close')" @click="ui.selKeyId = null"><Icon name="close" :size="10" /></button>
    </div>
    <div class="p-body">
      <div v-if="key.orbit" class="blk"><span class="mini">{{ t('key_orbit') }}</span></div>
      <div class="blk">
        <UiSlider :model-value="key.t" :min="0" :max="maxT" :step="0.1" :label="t('key_time')" :display="(v) => v.toFixed(1) + 's'" @update:model-value="(v) => patch({ t: v }, (k) => (k.t = v))" />
        <UiSlider :model-value="key.hold" :min="0" :max="30" :step="0.1" :label="t('key_hold')" :display="(v) => v.toFixed(1) + 's'" @update:model-value="(v) => patch({ hold: v }, (k) => (k.hold = v))" />
        <UiSlider :model-value="key.fov" :min="session.config.fov.min" :max="session.config.fov.max" :step="0.5" :label="t('fov')" @update:model-value="(v) => patch({ fov: v }, (k) => (k.fov = v))" />
      </div>

      <div class="blk">
        <div class="blk-head">{{ t('interp') }}</div>
        <div class="pill-group">
          <button v-for="i in interps" :key="i" :class="{ on: key.interp === i }" @click="patch({ interp: i }, (k) => (k.interp = i))">{{ t('interp_' + i) }}</button>
        </div>
        <div class="blk-head">{{ t('ease') }}</div>
        <div class="pill-group pill-grid">
          <button v-for="e in eases" :key="e" :class="{ on: key.ease === e }" :title="t('ease_' + e + '_tip')" @click="patch({ ease: e }, (k) => (k.ease = e))">{{ t('ease_' + e) }}</button>
        </div>
        <span class="mini">{{ t('ease_' + key.ease + '_tip') }}</span>
        <BezierEditor v-if="key.ease === 'bezier'" :model-value="key.bez" @update:model-value="(v) => patch({ bez: v }, (k) => (k.bez = v))" />
        <button class="ui-btn small ghost" @click="applyAll">{{ t('apply_all_keys') }}</button>
      </div>

      <div v-if="session.config.dof.enabled" class="blk">
        <UiToggle :model-value="key.dof.on" :label="t('dof_on')" @update:model-value="(v) => setDof('on', v)" />
        <template v-if="key.dof.on">
          <UiSlider :model-value="key.dof.near" :min="0" :max="100" :step="0.1" :label="t('dof_near')" @update:model-value="(v) => setDof('near', v)" />
          <UiSlider :model-value="key.dof.far" :min="0" :max="500" :step="0.5" :label="t('dof_far')" @update:model-value="(v) => setDof('far', v)" />
          <UiSlider :model-value="key.dof.str" :min="0" :max="1" :step="0.05" :label="t('dof_strength')" @update:model-value="(v) => setDof('str', v)" />
        </template>
      </div>

      <div class="blk">
        <div class="blk-head">{{ t('key_shake') }}</div>
        <UiToggle :model-value="!!key.shake" :label="t('key_shake_own')" @update:model-value="toggleShake" />
        <template v-if="key.shake">
          <div class="pill-group pill-grid">
            <button v-for="p in shakePresets" :key="p" :class="{ on: key.shake.preset === p }" @click="setShake('preset', p)">{{ t('shake_' + p) }}</button>
          </div>
          <UiSlider v-if="key.shake.preset !== 'none'" :model-value="key.shake.amount" :min="0" :max="3" :step="0.05" :label="t('shake_amount')" @update:model-value="(v) => setShake('amount', v)" />
          <UiSlider :model-value="key.shake.speed" :min="0" :max="1" :step="0.05" :label="t('shake_speed')" @update:model-value="(v) => setShake('speed', v)" />
          <UiSlider :model-value="key.shake.whip" :min="0" :max="1" :step="0.05" :label="t('shake_whip')" @update:model-value="(v) => setShake('whip', v)" />
        </template>
        <span class="mini">{{ key.shake ? t('key_shake_on') : t('key_shake_off') }}</span>
      </div>

      <div class="blk-head" style="padding: 0 2px">{{ t('key_env') }}</div>
      <EnvFields :env="key.env || {}" @set="setEnv" @clear="clearEnv" />

      <div class="row wrap">
        <button class="ui-btn small ghost" @click="fetchNui('keyGoto', { shotId: shot.id, keyId: key.id })">{{ t('key_goto') }}</button>
        <button class="ui-btn small ghost" @click="fetchNui('keyFromCamera', { shotId: shot.id, keyId: key.id })">{{ t('key_from_cam') }}</button>
        <button class="ui-btn small danger" @click="remove"><Icon name="trash" :size="12" />{{ t('delete') }}</button>
      </div>
    </div>
  </div>
</template>
