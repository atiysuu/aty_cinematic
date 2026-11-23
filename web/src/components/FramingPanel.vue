<script setup>
// Framing aids on one screen: guides (switch + what to draw), crop frame for vertical exports,
// cinema bars. Drawn by Overlays.vue; the choices are kept per browser (ui store).
import { useSession } from '@/stores/session'
import { useProject } from '@/stores/project'
import { useUi } from '@/stores/ui'
import { fetchNui } from '@/utils/nui'
import { t } from '@/locale'
import UiSlider from './ui/UiSlider.vue'
import UiToggle from './ui/UiToggle.vue'

const session = useSession()
const project = useProject()
const ui = useUi()

const crops = [
  { value: 0, label: () => t('fr_crop_off') },
  { value: 0.5625, label: () => '9:16' },
  { value: 0.8, label: () => '4:5' },
  { value: 1, label: () => '1:1' },
  { value: 1.3333, label: () => '4:3' },
]
const grids = [['thirds', 'fr_thirds'], ['golden', 'fr_golden'], ['cross', 'fr_cross'], ['diagonals', 'fr_diagonals'], ['safe', 'fr_safe_short']]
const gauges = [['level', 'fr_level_short'], ['info', 'fr_info_short'], ['inClean', 'fr_in_clean_short']]

function set(field, value) {
  ui.guides[field] = value
  ui.saveGuides()
}
// Picking something to draw turns the guides on: no second click on the main switch.
function flip(field) {
  const next = !ui.guides[field]
  ui.guides[field] = next
  if (next && field !== 'inClean') ui.guides.on = true
  ui.saveGuides()
}
function setCrop(value) {
  ui.guides.crop = value
  if (value > 0) ui.guides.on = true
  ui.saveGuides()
}
function setRatio(r) {
  project.markEdit()
  if (project.doc) project.doc.settings.letterbox = r
  fetchNui('settingsSet', { letterbox: r })
}
</script>

<template>
  <div class="p-body">
    <div class="blk">
      <UiToggle :model-value="ui.guides.on" :label="t('fr_guides')" @update:model-value="(v) => set('on', v)" />
      <div class="row wrap">
        <button v-for="[f, label] in grids" :key="f" class="opt" :class="{ on: ui.guides[f] }" :aria-pressed="ui.guides[f]" @click="flip(f)">{{ t(label) }}</button>
      </div>
      <div class="row wrap">
        <button v-for="[f, label] in gauges" :key="f" class="opt" :class="{ on: ui.guides[f] }" :aria-pressed="ui.guides[f]" @click="flip(f)">{{ t(label) }}</button>
      </div>
      <UiSlider :model-value="ui.guides.opacity" :min="0.1" :max="1" :step="0.05" :label="t('fr_opacity')" :display="(v) => '%' + Math.round(v * 100)" @update:model-value="(v) => set('opacity', v)" />
    </div>

    <div class="blk">
      <div class="blk-head">{{ t('fr_crop') }}</div>
      <div class="pill-group">
        <button v-for="c in crops" :key="c.value" :class="{ on: Math.abs(ui.guides.crop - c.value) < 0.001 }" @click="setCrop(c.value)">{{ c.label() }}</button>
      </div>
      <UiSlider v-if="ui.guides.crop > 0" :model-value="ui.guides.mask" :min="0.2" :max="1" :step="0.05" :label="t('fr_mask')" :display="(v) => '%' + Math.round(v * 100)" @update:model-value="(v) => set('mask', v)" />
    </div>

    <div class="blk">
      <UiToggle v-model="ui.letterboxOn" :label="t('letterbox')" />
      <div v-if="ui.letterboxOn && project.doc" class="pill-group">
        <button v-for="r in session.config.ratios" :key="r" :class="{ on: Math.abs(project.doc.settings.letterbox - r) < 0.001 }" @click="setRatio(r)">{{ r }}</button>
      </div>
    </div>

    <span class="mini">{{ t('fr_note') }}</span>
  </div>
</template>
