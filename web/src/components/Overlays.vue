<script setup>
// Letterbox bars, editor-only frame guides, help card, gizmo hint.
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useSession } from '@/stores/session'
import { useProject } from '@/stores/project'
import { useUi } from '@/stores/ui'
import { fetchNui } from '@/utils/nui'
import { t } from '@/locale'

const session = useSession()
const project = useProject()
const ui = useUi()

const vw = ref(window.innerWidth)
const vh = ref(window.innerHeight)
const onResize = () => { vw.value = window.innerWidth; vh.value = window.innerHeight }
onMounted(() => window.addEventListener('resize', onResize))
onBeforeUnmount(() => window.removeEventListener('resize', onResize))

const ratio = computed(() => (project.doc && project.doc.settings.letterbox) || 2.39)
const barH = computed(() => Math.max(0, (vh.value - vw.value / ratio.value) / 2))
const clean = computed(() => session.state.clean)
const gizmo = computed(() => session.state.gizmo || { active: false })

// Framing guides: everything is drawn inside the frame that will survive (crop frame, else the
// cinema bars, else the whole screen).
const g = computed(() => ui.guides)
const showGuides = computed(() => g.value.on && (!clean.value || g.value.inClean))
const frame = computed(() => {
  const W = vw.value, H = vh.value
  let w = W, h = H
  if (g.value.crop > 0) {
    w = Math.min(W, H * g.value.crop)
    h = Math.min(H, w / g.value.crop)
  } else if (ui.letterboxOn) {
    h = Math.min(H, W / ratio.value)
  }
  return { left: (W - w) / 2, top: (H - h) / 2, width: w, height: h }
})
const frameStyle = computed(() => ({
  left: frame.value.left + 'px', top: frame.value.top + 'px', width: frame.value.width + 'px', height: frame.value.height + 'px',
  color: `rgba(255, 255, 255, ${g.value.opacity})`,
}))
const cropMasks = computed(() => {
  if (!(g.value.crop > 0)) return []
  const f = frame.value, o = { background: `rgba(0, 0, 0, ${g.value.mask})` }
  const out = []
  if (f.left > 0.5) {
    out.push({ ...o, left: 0, top: 0, bottom: 0, width: f.left + 'px' })
    out.push({ ...o, right: 0, top: 0, bottom: 0, width: f.left + 'px' })
  }
  if (f.top > 0.5) {
    out.push({ ...o, left: 0, right: 0, top: 0, height: f.top + 'px' })
    out.push({ ...o, left: 0, right: 0, bottom: 0, height: f.top + 'px' })
  }
  return out
})
const roll = computed(() => (session.cam.rot ? session.cam.rot[1] : 0))
const tilt = computed(() => (session.cam.rot ? session.cam.rot[0] : 0))
const levelOk = computed(() => Math.abs(roll.value) < 0.25)
// GTA's FOV is the vertical angle: full-frame equivalent = 12 mm / tan(fov / 2) (24 mm sensor height)
const focal = computed(() => {
  const fov = session.cam.fov || 50
  return 12 / Math.tan((fov * Math.PI) / 360)
})
const clock = (s) => {
  const v = Math.max(0, s || 0)
  return String(Math.floor(v / 60)).padStart(2, '0') + ':' + (v % 60).toFixed(2).padStart(5, '0')
}

const controls = ['help_move', 'help_look', 'help_speed', 'help_fov', 'help_roll', 'help_exit']

// Quick-start card: shown until dismissed (remembered per browser, works without storage too).
const GUIDE_KEY = 'aty_cinematic.guideDone'
const readGuideDone = () => { try { return localStorage.getItem(GUIDE_KEY) === '1' } catch (e) { return false } }
const guideDone = ref(readGuideDone())
const hideGuide = () => {
  guideDone.value = true
  try { localStorage.setItem(GUIDE_KEY, '1') } catch (e) { /* storage unavailable: hidden for this session only */ }
}
const guideSteps = ['guide_1', 'guide_2', 'guide_3', 'guide_4']

// Clean view hides everything, so say how to get back, briefly, then get out of the shot.
const cleanHint = ref(false)
let cleanTimer = null
watch(clean, (on) => {
  clearTimeout(cleanTimer)
  cleanHint.value = !!on
  if (on) cleanTimer = setTimeout(() => { cleanHint.value = false }, 3500)
})
onBeforeUnmount(() => clearTimeout(cleanTimer))
</script>

<template>
  <template v-if="ui.letterboxOn && barH > 0">
    <div class="letterbox-bar" :style="{ top: 0, height: barH + 'px' }" />
    <div class="letterbox-bar" :style="{ bottom: 0, height: barH + 'px' }" />
  </template>

  <template v-if="showGuides">
    <div v-for="(m, i) in cropMasks" :key="i" class="frame-mask" :style="m" />
    <div class="guides" :style="frameStyle">
      <div v-if="g.crop > 0" class="frame-edge" />
      <template v-if="g.thirds">
        <i style="left: 33.333%; top: 0; bottom: 0; width: 1px" />
        <i style="left: 66.666%; top: 0; bottom: 0; width: 1px" />
        <i style="top: 33.333%; left: 0; right: 0; height: 1px" />
        <i style="top: 66.666%; left: 0; right: 0; height: 1px" />
      </template>
      <template v-if="g.golden">
        <i class="phi" style="left: 38.197%; top: 0; bottom: 0; width: 1px" />
        <i class="phi" style="left: 61.803%; top: 0; bottom: 0; width: 1px" />
        <i class="phi" style="top: 38.197%; left: 0; right: 0; height: 1px" />
        <i class="phi" style="top: 61.803%; left: 0; right: 0; height: 1px" />
      </template>
      <svg v-if="g.diagonals" preserveAspectRatio="none" viewBox="0 0 100 100">
        <line x1="0" y1="0" x2="100" y2="100" /><line x1="100" y1="0" x2="0" y2="100" />
      </svg>
      <template v-if="g.safe">
        <div class="safe" style="inset: 5%" /><div class="safe" style="inset: 10%" />
      </template>
      <template v-if="g.cross">
        <i style="left: 50%; top: 50%; width: 36px; height: 1px; margin: 0 0 0 -18px" />
        <i style="left: 50%; top: 50%; width: 1px; height: 36px; margin: -18px 0 0 0" />
      </template>
      <template v-if="g.level">
        <i class="level-ref" style="left: 34%" /><i class="level-ref" style="right: 34%" />
        <div class="level" :class="{ ok: levelOk }" :style="{ transform: `rotate(${-roll}deg)` }" />
        <div class="guide-chip level-read" :class="{ ok: levelOk }">{{ t('fr_roll') }} {{ roll.toFixed(1) }}° · {{ t('fr_tilt') }} {{ tilt.toFixed(1) }}°</div>
      </template>
      <div v-if="g.info" class="guide-chip info-read">
        FOV {{ (session.cam.fov || 0).toFixed(1) }}° ≈ {{ focal.toFixed(0) }} mm · {{ clock(session.playhead.t) }} / {{ clock(project.duration) }}
      </div>
    </div>
  </template>

  <div v-if="gizmo.active && !clean" class="gizmo-hint glass ui-blocking">
    <span>{{ t('gizmo_mode') }}: <b style="color: var(--accent)">{{ gizmo.mode === 'rotate' ? t('gizmo_rotate') : t('gizmo_move') }}</b></span>
    <span>{{ t('gizmo_space') }}: <b style="color: var(--accent)">{{ gizmo.space === 'local' ? t('gizmo_local') : t('gizmo_world') }}</b></span>
    <span class="mini">{{ t('gizmo_keys') }}</span>
    <button class="ui-btn small accent" @click="fetchNui('gizmoStop')">{{ t('done') }}</button>
  </div>

  <div v-if="session.state.placer && !clean" class="gizmo-hint glass ui-blocking">
    <span>{{ t('placer_hint') }}</span>
    <span class="mini">{{ t('placer_keys') }}</span>
    <button class="ui-btn small accent" @click="fetchNui('placerStop', { keep: true })">{{ t('done') }}</button>
    <button class="ui-btn small ghost" @click="fetchNui('placerStop', { keep: false })">{{ t('placer_cancel') }}</button>
  </div>

  <div v-if="ui.helpOpen && !clean" class="help glass ui-blocking">
    <h3>{{ t('help') }}</h3>
    <div v-for="k in session.keys" :key="k.command" class="kv"><span>{{ k.label }}</span><kbd>{{ k.key }}</kbd></div>
    <div v-for="c in controls" :key="c" class="kv"><span>{{ t(c) }}</span></div>
    <span class="mini">{{ t('help_rebind') }}</span>
  </div>

  <div v-if="!guideDone && !clean && !ui.helpOpen" class="guide glass ui-blocking">
    <h3>{{ t('guide_title') }}</h3>
    <div v-for="(s, i) in guideSteps" :key="s" class="guide-step"><b>{{ i + 1 }}</b><span>{{ t(s) }}</span></div>
    <button class="ui-btn small accent" @click="hideGuide">{{ t('guide_hide') }}</button>
  </div>

  <transition name="fade">
    <div v-if="cleanHint" class="clean-hint glass">{{ t('clean_hint') }}</div>
  </transition>
</template>
