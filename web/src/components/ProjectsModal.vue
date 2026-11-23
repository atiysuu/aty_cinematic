<script setup>
import { computed, ref, watch } from 'vue'
import { useProject } from '@/stores/project'
import { useUi } from '@/stores/ui'
import { fetchNui } from '@/utils/nui'
import { t } from '@/locale'
import Icon from './ui/Icon.vue'

const project = useProject()
const ui = useUi()

const newName = ref('')
const renaming = ref(null)
const renameText = ref('')
const confirmDelete = ref(null)
const busy = ref(false)

const show = computed(() => ui.projectsOpen || !project.doc)
const canClose = computed(() => !!project.doc)

watch(show, (v) => {
  if (v) fetchNui('projectsList')
  confirmDelete.value = null
  renaming.value = null
})

const fmtSize = (b) => (b > 1024 ? (b / 1024).toFixed(1) + ' KB' : b + ' B')

async function create() {
  if (busy.value) return
  busy.value = true
  const res = await fetchNui('projectNew', { name: newName.value.trim() || t('untitled') })
  busy.value = false
  if (res.ok) { newName.value = ''; ui.projectsOpen = false }
}
async function open(p) {
  if (busy.value) return
  busy.value = true
  const res = await fetchNui('projectOpen', { id: p.id })
  busy.value = false
  if (res.ok) ui.projectsOpen = false
}
function startRename(p) { renaming.value = p.id; renameText.value = p.name }
async function commitRename(p) {
  const name = renameText.value.trim()
  renaming.value = null
  if (name && name !== p.name) await fetchNui('projectRename', { id: p.id, name })
}
function duplicate(p) { fetchNui('projectDuplicate', { id: p.id, name: p.name + ' copy' }) }
function remove(p) {
  if (confirmDelete.value !== p.id) { confirmDelete.value = p.id; return }
  confirmDelete.value = null
  fetchNui('projectDelete', { id: p.id })
}
</script>

<template>
  <Teleport to="#stage">
    <div class="ui-modal-back ui-blocking" :class="{ show }" role="dialog" aria-modal="true" :aria-label="t('projects')">
      <div class="ui-modal" style="width: 420px">
        <button v-if="canClose" class="m-x" :aria-label="t('close')" @click="ui.projectsOpen = false"><Icon name="close" :size="8" /></button>
        <div class="m-body">
          <div class="m-title">{{ t('projects') }}</div>
          <div class="row" style="width: 100%">
            <input v-model="newName" class="cine-input" :placeholder="t('project_name')" maxlength="48" @keydown.enter="create" />
            <button class="ui-btn small accent" :disabled="busy" @click="create"><Icon name="plus" :size="12" />{{ t('project_new') }}</button>
          </div>
          <div v-if="!project.projects.length" class="empty" style="width: 100%">{{ t('no_projects') }}</div>
          <div class="modal-list">
            <div v-for="p in project.projects" :key="p.id" class="item" :class="{ sel: project.doc && project.doc.id === p.id }" @click="renaming !== p.id && open(p)">
              <template v-if="renaming === p.id">
                <input v-model="renameText" class="cine-input" maxlength="48" @click.stop @keydown.enter="commitRename(p)" @keydown.esc="renaming = null" @blur="commitRename(p)" />
              </template>
              <template v-else>
                <span class="t">{{ p.name }}</span>
                <span class="s">{{ p.shots }} {{ t('shots') }} / {{ fmtSize(p.bytes) }}</span>
              </template>
              <button class="ui-icon-btn sm" :title="t('rename')" @click.stop="startRename(p)"><Icon name="edit" :size="10" /></button>
              <button class="ui-icon-btn sm" :title="t('duplicate')" @click.stop="duplicate(p)"><Icon name="copy" :size="10" /></button>
              <button class="ui-icon-btn sm danger-h" :class="{ on: confirmDelete === p.id }" :title="confirmDelete === p.id ? t('confirm') : t('delete')" @click.stop="remove(p)"><Icon name="trash" :size="10" /></button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
