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
import UiColorPicker from './ui/UiColorPicker.vue'

const session = useSession()
const project = useProject()
const ui = useUi()

const sel = computed(() => project.lights.find((l) => l.id === ui.selLightId) || null)
const full = computed(() => project.lights.length >= session.config.lights.max)
const gizmoOn = computed(() => session.state.gizmo && session.state.gizmo.active && session.state.gizmo.id === ui.selLightId)
const enabledInShot = computed(() => {
  const s = project.shot
  return !(s && sel.value && s.lights && s.lights[sel.value.id] === false)
})
const color = computed(() => {
  const c = sel.value ? sel.value.color : [255, 214, 170]
  const hex = '#' + c.map((v) => v.toString(16).padStart(2, '0')).join('')
  return { id: null, name: 'Custom', hex, rgb: [...c] }
})

async function add(type) {
  const res = await fetchNui('lightAdd', { type })
  if (res.ok && res.id) ui.selLightId = res.id
}
// optimistic local edit + throttled send (Lua sanitizes and echoes the project back)
function setField(field, value) {
  if (!sel.value) return
  project.markEdit()
  sel.value[field] = value
  sendThrottled('light_' + sel.value.id + field, 'lightUpdate', { id: sel.value.id, patch: { [field]: value } })
}
function setColor(c) {
  if (!c || !Array.isArray(c.rgb) || !sel.value) return
  setField('color', c.rgb.map((v) => Math.round(v)))
}
function setEnabled(on) {
  if (!sel.value || !project.shot) return
  fetchNui('lightShot', { shotId: project.shot.id, id: sel.value.id, on })
}
</script>

<template>
  <div class="p-body">
    <div class="blk">
      <div class="blk-head">{{ t('add_light') }}<span class="v">{{ project.lights.length }} / {{ session.config.lights.max }}</span></div>
      <div class="row">
        <button class="ui-btn small ghost grow" :disabled="full" @click="add('point')"><Icon name="plus" :size="12" />{{ t('point') }}</button>
        <button class="ui-btn small ghost grow" :disabled="full" @click="add('spot')"><Icon name="plus" :size="12" />{{ t('spot') }}</button>
      </div>
    </div>

    <div class="blk">
      <div class="blk-head">{{ t('lights') }}</div>
      <div v-if="!project.lights.length" class="empty">{{ t('no_lights') }}</div>
      <div class="list">
        <div v-for="l in project.lights" :key="l.id" class="item" :class="{ sel: l.id === ui.selLightId }" @click="ui.selLightId = l.id">
          <span class="t">{{ l.name }}</span><span class="s">{{ t(l.type) }}</span>
        </div>
      </div>
    </div>

    <div v-if="sel" class="blk">
      <div class="blk-head">{{ sel.name }}</div>
      <div class="row wrap">
        <button class="ui-btn small" :class="gizmoOn ? 'accent' : 'ghost'" @click="fetchNui('lightPlace', { id: sel.id })"><Icon name="target" :size="12" />{{ t('place') }}</button>
        <button class="ui-btn small danger" @click="fetchNui('lightDelete', { id: sel.id })"><Icon name="trash" :size="12" />{{ t('delete') }}</button>
      </div>
      <UiColorPicker :model-value="color" @update:model-value="setColor" />
      <UiSlider :model-value="sel.intensity" :min="0" :max="50" :step="0.1" :label="t('intensity')" @update:model-value="(v) => setField('intensity', v)" />
      <UiSlider :model-value="sel.range" :min="0.5" :max="100" :step="0.5" :label="t('range')" @update:model-value="(v) => setField('range', v)" />
      <template v-if="sel.type === 'spot'">
        <UiSlider :model-value="sel.radius" :min="1" :max="90" :step="1" :label="t('cone')" @update:model-value="(v) => setField('radius', v)" />
        <UiSlider :model-value="sel.roundness" :min="0" :max="50" :step="0.5" :label="t('roundness')" @update:model-value="(v) => setField('roundness', v)" />
        <UiSlider :model-value="sel.falloff" :min="0" :max="50" :step="0.5" :label="t('falloff')" @update:model-value="(v) => setField('falloff', v)" />
      </template>
      <UiToggle :model-value="sel.shadow" :label="t('shadow')" @update:model-value="(v) => setField('shadow', v)" />
      <UiToggle :model-value="enabledInShot" :label="t('enabled_shot')" :disabled="!project.shot" @update:model-value="setEnabled" />
    </div>
  </div>
</template>
