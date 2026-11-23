<script setup>
import { computed } from 'vue'
import { useSession } from '@/stores/session'
import { useProject } from '@/stores/project'
import { useUi } from '@/stores/ui'
import { fetchNui } from '@/utils/nui'
import { t } from '@/locale'
import Icon from './ui/Icon.vue'

const session = useSession()
const project = useProject()
const ui = useUi()

const tabs = ['camera', 'presets', 'actors', 'lights', 'env', 'framing']
const rigs = ['free', 'orbit', 'follow']
const name = computed(() => (project.doc ? project.doc.name : t('no_project')))
const modeLabel = computed(() => (session.state.mode === 'preview' ? t('mode_preview') : t('mode_edit')))
const saveLabel = computed(() => (session.state.saving ? t('saving') : t('save')))

function setRig(rig) {
  fetchNui('setRig', { rig, target: ui.selActorId || undefined })
}
</script>

<template>
  <div class="bar glass ui-blocking">
    <div class="name" :data-tip="t('project')">
      <i class="dirty-dot" :class="{ clean: !session.state.dirty }" />
      <span>{{ name }}</span>
    </div>
    <span class="chip" :class="session.state.mode === 'preview' ? 'accent' : ''">{{ modeLabel }}</span>
    <div class="sep" />
    <div class="tabs" role="tablist" :aria-label="t('rig')">
      <button v-for="r in rigs" :key="r" class="tab" :class="{ on: session.state.rig === r }" role="tab" @click="setRig(r)">{{ t('rig_' + r) }}</button>
    </div>
    <div class="tabs" role="tablist">
      <button v-for="p in tabs" :key="p" class="tab" :class="{ on: ui.panel === p }" role="tab" @click="ui.panel = p">{{ t('panel_' + p) }}</button>
    </div>
    <div class="sep" />
    <button class="ui-icon-btn" :title="t('projects')" @click="ui.projectsOpen = true"><Icon name="folder" /></button>
    <button class="ui-btn small accent" :disabled="!project.doc || session.state.saving" @click="fetchNui('projectSave')">
      <Icon name="save" :size="12" />{{ saveLabel }}
    </button>
    <button class="ui-icon-btn" :class="{ on: session.state.cursor }" :title="t('cursor')" @click="fetchNui('setCursor', { on: !session.state.cursor })"><Icon name="cursor" /></button>
    <button class="ui-icon-btn" :title="t('clean')" @click="fetchNui('setClean', { on: true })"><Icon name="eye" /></button>
    <button class="ui-icon-btn" :class="{ on: ui.helpOpen }" :title="t('help')" @click="ui.helpOpen = !ui.helpOpen"><Icon name="help" /></button>
    <button class="ui-icon-btn danger-h" :title="t('close')" @click="fetchNui('close')"><Icon name="close" /></button>
  </div>
</template>
