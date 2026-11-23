<script setup>
import { computed, onMounted, watch } from 'vue'
import { useSession } from '@/stores/session'
import { useUi } from '@/stores/ui'
import { fetchNui, initPointerTracking } from '@/utils/nui'
import { initEvents } from '@/utils/events'
import { t } from '@/locale'
import DirectorBar from './components/DirectorBar.vue'
import CameraPanel from './components/CameraPanel.vue'
import ActorsPanel from './components/ActorsPanel.vue'
import LightsPanel from './components/LightsPanel.vue'
import EnvPanel from './components/EnvPanel.vue'
import PresetsPanel from './components/PresetsPanel.vue'
import FramingPanel from './components/FramingPanel.vue'
import Timeline from './components/Timeline.vue'
import KeyInspector from './components/KeyInspector.vue'
import ProjectsModal from './components/ProjectsModal.vue'
import Overlays from './components/Overlays.vue'

const session = useSession()
const ui = useUi()

const panels = { camera: CameraPanel, presets: PresetsPanel, actors: ActorsPanel, lights: LightsPanel, env: EnvPanel, framing: FramingPanel }
const panel = computed(() => panels[ui.panel] || CameraPanel)
const clean = computed(() => session.state.clean)

// The actor picked in the Actors panel is outlined in the world. Only while that panel is open:
// in the other panels the picture should stay clean for framing.
watch(() => (session.visible && ui.panel === 'actors' ? ui.selActorIds.join(',') : ''), (list) => {
  if (session.visible) fetchNui('actorSelect', { ids: list ? list.split(',') : [] })
})

onMounted(() => {
  initEvents()
  initPointerTracking()
  fetchNui('nuiReady')
  // Space is the play / pause key mapping (the game gets it either way). In the page it would
  // scroll the panel that was clicked last and press the focused control: swallow it, except
  // while typing in a text field.
  const typing = (el) => !!el && (el.isContentEditable || el.tagName === 'TEXTAREA'
    || (el.tagName === 'INPUT' && el.type !== 'range' && el.type !== 'checkbox'))
  const swallowSpace = (e) => {
    if ((e.code === 'Space' || e.key === ' ') && !typing(e.target)) {
      e.preventDefault()
      e.stopPropagation()
    }
  }
  window.addEventListener('keydown', swallowSpace, true)
  window.addEventListener('keyup', swallowSpace, true)
  // Buttons must not keep focus: Space is the play/pause key mapping, a focused button would click again.
  document.addEventListener('click', (e) => {
    const b = e.target && e.target.closest ? e.target.closest('button') : null
    if (b) b.blur()
  })
})
</script>

<template>
  <div v-if="session.visible" class="cine-root">
    <Overlays />
    <template v-if="!clean">
      <DirectorBar />
      <div class="dock-right glass ui-blocking">
        <div class="p-head">{{ t('panel_' + ui.panel) }}</div>
        <component :is="panel" />
      </div>
      <KeyInspector />
      <Timeline />
      <ProjectsModal />
    </template>
  </div>
</template>
