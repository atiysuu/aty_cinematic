<script setup>
// Shared environment editor: the live environment panel and the env part of a keyframe.
// A field is "set" when it exists in `env`; unset fields are inherited (key) or left alone (live).
import { computed, ref, watch } from 'vue'
import { useSession } from '@/stores/session'
import { fetchNui } from '@/utils/nui'
import { t } from '@/locale'
import UiSlider from './ui/UiSlider.vue'
import UiSelect from './ui/UiSelect.vue'

const props = defineProps({ env: { type: Object, default: () => ({}) } })
const emit = defineEmits(['set', 'clear'])
const session = useSession()

const has = (f) => props.env[f] !== undefined
const weatherOptions = computed(() => session.config.weathers.map((w) => ({ value: w, label: w })))

const hhmm = (m) => {
  const v = Math.max(0, Math.min(1439, Math.round(m)))
  return String(Math.floor(v / 60)).padStart(2, '0') + ':' + String(v % 60).padStart(2, '0')
}

function toggle(field, def) {
  if (has(field)) emit('clear', field)
  else emit('set', field, def)
}

// timecycle search
const tcQuery = ref('')
const tcResults = ref([])
let timer = null
watch(tcQuery, (q) => {
  clearTimeout(timer)
  timer = setTimeout(async () => {
    const res = await fetchNui('lookup', { kind: 'timecycle', q })
    tcResults.value = res.ok ? res.items : []
  }, 150)
})
</script>

<template>
  <div class="env-fields">
    <div class="blk">
      <div class="blk-head">
        {{ t('env_tod') }}
        <button class="chip" :class="{ accent: has('tod') }" @click="toggle('tod', 720)">{{ has('tod') ? t('set') : t('inherit') }}</button>
      </div>
      <template v-if="has('tod')">
        <UiSlider :model-value="env.tod" :min="0" :max="1439" :step="5" :display="hhmm" @update:model-value="(v) => emit('set', 'tod', v)" />
        <div class="pill-group">
          <button :class="{ on: (env.todDir || 'short') === 'short' }" @click="emit('set', 'todDir', 'short')">{{ t('tod_short') }}</button>
          <button :class="{ on: env.todDir === 'forward' }" @click="emit('set', 'todDir', 'forward')">{{ t('tod_forward') }}</button>
        </div>
      </template>
    </div>

    <div class="blk">
      <div class="blk-head">
        {{ t('env_weather') }}
        <button class="chip" :class="{ accent: has('weather') }" @click="toggle('weather', 'CLEAR')">{{ has('weather') ? t('set') : t('inherit') }}</button>
      </div>
      <UiSelect v-if="has('weather')" :model-value="env.weather" :options="weatherOptions" @update:model-value="(v) => emit('set', 'weather', v)" />
    </div>

    <div class="blk">
      <div class="blk-head">
        {{ t('env_timecycle') }}
        <button class="chip" :class="{ accent: has('timecycle') }" @click="toggle('timecycle', '')">{{ has('timecycle') ? t('set') : t('inherit') }}</button>
      </div>
      <template v-if="has('timecycle')">
        <div class="row">
          <span class="val grow">{{ env.timecycle || t('tc_none') }}</span>
          <button class="ui-btn small ghost" @click="emit('set', 'timecycle', '')">{{ t('clear') }}</button>
        </div>
        <input v-model="tcQuery" class="cine-input" :placeholder="t('search')" />
        <div class="picker-list">
          <div v-for="n in tcResults" :key="n" class="item" :class="{ sel: n === env.timecycle }" @click="emit('set', 'timecycle', n)"><span class="t">{{ n }}</span></div>
        </div>
        <UiSlider :model-value="env.tcStrength ?? 1" :min="0" :max="1" :step="0.05" :label="t('tc_strength')" @update:model-value="(v) => emit('set', 'tcStrength', v)" />
      </template>
    </div>

    <div class="blk">
      <div class="blk-head">
        {{ t('env_timescale') }}
        <button class="chip" :class="{ accent: has('timeScale') }" @click="toggle('timeScale', 1)">{{ has('timeScale') ? t('set') : t('inherit') }}</button>
      </div>
      <UiSlider v-if="has('timeScale')" :model-value="env.timeScale" :min="session.config.timeScaleMin" :max="1" :step="0.05" @update:model-value="(v) => emit('set', 'timeScale', v)" />
    </div>

    <div class="blk">
      <div class="blk-head">
        {{ t('env_wind') }}
        <button class="chip" :class="{ accent: has('wind') }" @click="toggle('wind', 0)">{{ has('wind') ? t('set') : t('inherit') }}</button>
      </div>
      <UiSlider v-if="has('wind')" :model-value="env.wind" :min="0" :max="12" :step="0.5" @update:model-value="(v) => emit('set', 'wind', v)" />
      <div class="blk-head">
        {{ t('env_rain') }}
        <button class="chip" :class="{ accent: has('rain') }" @click="toggle('rain', 0)">{{ has('rain') ? t('set') : t('inherit') }}</button>
      </div>
      <UiSlider v-if="has('rain')" :model-value="env.rain" :min="0" :max="1" :step="0.05" @update:model-value="(v) => emit('set', 'rain', v)" />
    </div>

    <div class="blk">
      <div class="blk-head">{{ t('env_blackout') }}</div>
      <div class="pill-group">
        <button :class="{ on: !has('blackout') }" @click="emit('clear', 'blackout')">{{ t('inherit') }}</button>
        <button :class="{ on: env.blackout === true }" @click="emit('set', 'blackout', true)">{{ t('on') }}</button>
        <button :class="{ on: env.blackout === false }" @click="emit('set', 'blackout', false)">{{ t('off') }}</button>
      </div>
      <div class="blk-head">{{ t('env_population') }}</div>
      <div class="pill-group">
        <button :class="{ on: !has('population') }" @click="emit('clear', 'population')">{{ t('inherit') }}</button>
        <button :class="{ on: env.population === true }" @click="emit('set', 'population', true)">{{ t('env_clear_pop') }}</button>
        <button :class="{ on: env.population === false }" @click="emit('set', 'population', false)">{{ t('off') }}</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.env-fields { display: flex; flex-direction: column; gap: 10px; }
</style>
