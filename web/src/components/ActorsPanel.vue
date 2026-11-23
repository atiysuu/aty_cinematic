<script setup>
// Actors: add, pick one or several, move them, give them an emote.
// Several picked at once: they move together (mouse placing keeps the formation) and an emote
// goes to all of them, or a mix is dealt out so a crowd does not move in step.
import { computed, ref, watch } from 'vue'
import { useSession } from '@/stores/session'
import { useProject } from '@/stores/project'
import { useUi } from '@/stores/ui'
import { fetchNui } from '@/utils/nui'
import { t } from '@/locale'
import Icon from './ui/Icon.vue'
import UiToggle from './ui/UiToggle.vue'
import UiSlider from './ui/UiSlider.vue'

const session = useSession()
const project = useProject()
const ui = useUi()

// add ------------------------------------------------------------------------------------------
const addKind = ref('ped') // ped | vehicle
const query = ref('')
const results = ref([])
const useMyCar = ref(false)
const full = computed(() => project.actors.length >= session.config.actors.max)

let qTimer = null
async function runLookup(kind, q, target) {
  const res = await fetchNui('lookup', { kind, q })
  target.value = res.ok ? res.items : []
}
watch([query, addKind], () => {
  clearTimeout(qTimer)
  qTimer = setTimeout(() => runLookup(addKind.value, query.value, results), 150)
})
runLookup('ped', '', results)

async function add(kind, model) {
  const res = await fetchNui('actorAdd', { kind, model, useMyCar: kind === 'vehicle' && useMyCar.value })
  if (res.ok && res.id) ui.selectActors([res.id])
}

// selection ------------------------------------------------------------------------------------
const ids = computed(() => ui.selActorIds.filter((id) => project.actors.some((a) => a.id === id)))
const selected = computed(() => project.actors.filter((a) => ids.value.includes(a.id)))
const sel = computed(() => (selected.value.length === 1 ? selected.value[0] : null))
const peds = computed(() => selected.value.filter((a) => a.kind !== 'vehicle'))

function toggle(id) {
  ui.selectActors(ids.value.includes(id) ? ids.value.filter((x) => x !== id) : [...ids.value, id])
}
// plain click = only this one; Ctrl / Shift + click = add or remove it
function pick(a, e) {
  if (e.ctrlKey || e.shiftKey || e.metaKey) toggle(a.id)
  else ui.selectActors([a.id])
}
const selectAll = () => ui.selectActors(project.actors.map((a) => a.id))
const selectNone = () => ui.selectActors([])

const gizmoOn = computed(() => !!sel.value && session.state.gizmo && session.state.gizmo.active && session.state.gizmo.id === sel.value.id)
const placing = computed(() => !!session.state.placer && ids.value.includes(session.state.placer))
const placeWithMouse = () => fetchNui('actorDrop', { ids: ids.value })
async function removeSelected() {
  await fetchNui('actorsDelete', { ids: ids.value })
  ui.selectActors([])
}

// emotes ---------------------------------------------------------------------------------------
const CATS = ['all', 'idle', 'talk', 'gesture', 'phone', 'smoke', 'party', 'crowd', 'police', 'work', 'sport', 'sit']
const emotes = ref([])
const emoteQuery = ref('')
const emoteCat = ref('all')
const dict = ref('')
const clip = ref('')
runLookup('anim', '', emotes)

const shown = computed(() => {
  const q = emoteQuery.value.trim().toLowerCase()
  return emotes.value.filter((e) => (emoteCat.value === 'all' || e.cat === emoteCat.value) && (!q || e.label.toLowerCase().includes(q)))
})
const cats = computed(() => CATS.filter((c) => c === 'all' || emotes.value.some((e) => e.cat === c)))
const item = (e) => (e.kind === 'scenario' ? { kind: 'scenario', name: e.name } : { kind: 'anim', dict: e.dict, name: e.name, flag: e.flag })
const does = (a, e) => (e.kind === 'scenario' ? a.scenario === e.name : !!a.anim && a.anim.dict === e.dict && a.anim.name === e.name)
const isOn = (e) => peds.value.length > 0 && peds.value.every((a) => does(a, e))
const pedIds = () => peds.value.map((a) => a.id)

const play = (e) => fetchNui('actorsAnim', { ids: pedIds(), items: [item(e)] })
const stop = () => fetchNui('actorsAnim', { ids: pedIds(), clear: true })
// a different emote of the list on show for everyone: a crowd that does not move in step
function mix() {
  const pool = [...shown.value]
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    ;[pool[i], pool[j]] = [pool[j], pool[i]]
  }
  if (pool.length) fetchNui('actorsAnim', { ids: pedIds(), items: pool.slice(0, Math.max(peds.value.length, 1)).map(item) })
}
function playCustom() {
  if (!dict.value || !clip.value) return
  fetchNui('actorsAnim', { ids: pedIds(), items: [{ kind: 'anim', dict: dict.value.trim(), name: clip.value.trim(), flag: 1 }] })
}
// two-person emotes (hug, handshake): exactly two people. The one picked first stays where it is,
// the other steps in front of it.
const shared = ref([])
const pairScale = ref(1)
runLookup('shared', '', shared)
const picked = computed(() => ids.value.map((id) => project.actors.find((a) => a.id === id)).filter((a) => a && a.kind !== 'vehicle'))
const half = (a, c) => !!a.anim && a.anim.dict === c.dict && a.anim.name === c.name
const pairOn = (s) => {
  const [x, y] = picked.value
  if (!x || !y || x.pair !== y.id) return false
  return (half(x, s.a) && half(y, s.b)) || (half(x, s.b) && half(y, s.a))
}
const playShared = (s) => fetchNui('actorsPair', { ids: picked.value.map((a) => a.id), id: s.id, scale: pairScale.value })

const current = computed(() => {
  const a = sel.value
  if (!a || a.kind === 'vehicle') return ''
  const known = emotes.value.find((e) => does(a, e))
  if (known) return known.label
  if (a.anim) return a.anim.dict + ' / ' + a.anim.name
  return a.scenario || t('none')
})
</script>

<template>
  <div class="p-body">
    <div class="blk">
      <div class="blk-head">{{ t('add_actor') }}<span class="v">{{ project.actors.length }} / {{ session.config.actors.max }}</span></div>
      <div class="pill-group">
        <button :class="{ on: addKind === 'ped' }" @click="addKind = 'ped'">{{ t('ped') }}</button>
        <button :class="{ on: addKind === 'vehicle' }" @click="addKind = 'vehicle'">{{ t('vehicle') }}</button>
      </div>
      <UiToggle v-if="addKind === 'vehicle'" v-model="useMyCar" :label="t('use_my_car')" />
      <input v-model="query" class="cine-input" :placeholder="t('search')" />
      <div class="picker-list">
        <div v-for="m in results" :key="m.name || m" class="item" @click="!full && add(addKind, m.name || m)">
          <span class="t">{{ m.label || m }}</span><span v-if="m.label" class="s">{{ m.name }}</span><Icon name="plus" :size="12" />
        </div>
        <div v-if="!results.length" class="mini">{{ t('no_results') }}</div>
      </div>
      <button class="ui-btn small ghost" :disabled="full" @click="add('clone')">{{ t('clone_me') }}</button>
    </div>

    <div class="blk">
      <div class="blk-head">{{ t('actors') }}<span v-if="ids.length > 1" class="v">{{ t('n_selected', ids.length) }}</span></div>
      <div v-if="!project.actors.length" class="empty">{{ t('no_actors') }}</div>
      <template v-else>
        <div class="row">
          <button class="opt plain" @click="selectAll">{{ t('select_all') }}</button>
          <button class="opt plain" :disabled="!ids.length" @click="selectNone">{{ t('select_none') }}</button>
          <span class="mini grow hint-right">{{ t('multi_hint') }}</span>
        </div>
        <div class="list">
          <div v-for="a in project.actors" :key="a.id" class="item" :class="{ sel: ids.includes(a.id) }" @click="pick(a, $event)">
            <button class="check" :class="{ on: ids.includes(a.id) }" role="checkbox" :aria-checked="ids.includes(a.id)" :aria-label="a.name" @click.stop="toggle(a.id)" />
            <span class="t">{{ a.name }}</span><span class="s">{{ a.model || a.kind }}</span>
          </div>
        </div>
      </template>
    </div>

    <div v-if="selected.length" class="blk">
      <div class="blk-head">{{ sel ? sel.name : t('n_selected', selected.length) }}</div>
      <div v-if="sel" class="row wrap">
        <button class="ui-btn small" :class="gizmoOn ? 'accent' : 'ghost'" @click="fetchNui('actorPlace', { id: sel.id })"><Icon name="target" :size="12" />{{ t('place') }}</button>
        <button class="ui-btn small" :class="placing ? 'accent' : 'ghost'" @click="placeWithMouse">{{ t('place_look') }}</button>
        <button class="ui-btn small ghost" @click="fetchNui('actorDropAtCamera', { id: sel.id })">{{ t('drop_camera') }}</button>
        <button class="ui-btn small ghost" @click="fetchNui('setRig', { rig: 'orbit', target: sel.id })">{{ t('orbit_this') }}</button>
        <button class="ui-btn small ghost" @click="fetchNui('setRig', { rig: 'follow', target: sel.id })">{{ t('follow_this') }}</button>
        <button class="ui-btn small danger" @click="removeSelected"><Icon name="trash" :size="12" />{{ t('delete') }}</button>
      </div>
      <div v-else class="row wrap">
        <button class="ui-btn small" :class="placing ? 'accent' : 'ghost'" @click="placeWithMouse">{{ t('move_group') }}</button>
        <button class="ui-btn small danger" @click="removeSelected"><Icon name="trash" :size="12" />{{ t('delete_n', selected.length) }}</button>
      </div>
      <span v-if="!sel" class="mini">{{ t('move_group_hint') }}</span>
    </div>

    <div v-if="picked.length === 2" class="blk">
      <div class="blk-head">{{ t('shared_emotes') }}<span class="v">{{ picked[0].name }} + {{ picked[1].name }}</span></div>
      <div class="emote-grid">
        <button v-for="s in shared" :key="s.id" class="emote" :class="{ on: pairOn(s) }" :title="s.a.dict + ' / ' + s.a.name" @click="playShared(s)">
          <Icon :name="'em_' + s.icon" :size="22" /><span>{{ s.label }}</span>
        </button>
      </div>
      <UiSlider v-model="pairScale" :min="0.6" :max="1.6" :step="0.05" :label="t('shared_gap')" :display="(v) => '×' + v.toFixed(2)" />
      <span class="mini">{{ t('shared_hint') }}</span>
    </div>

    <div v-if="peds.length" class="blk">
      <div class="blk-head">{{ t('emotes') }}<span class="v">{{ sel ? current : t('n_peds', peds.length) }}</span></div>
      <span v-if="picked.length !== 2" class="mini">{{ t('shared_need_two') }}</span>
      <input v-model="emoteQuery" class="cine-input" :placeholder="t('search')" />
      <div class="row wrap chips">
        <button v-for="c in cats" :key="c" class="opt plain" :class="{ on: emoteCat === c }" @click="emoteCat = c">{{ t('emc_' + c) }}</button>
      </div>
      <div class="emote-grid">
        <button v-for="e in shown" :key="e.id" class="emote" :class="{ on: isOn(e) }" :title="e.kind === 'scenario' ? e.name : e.dict + ' / ' + e.name" @click="play(e)">
          <Icon :name="'em_' + e.icon" :size="22" /><span>{{ e.label }}</span>
        </button>
        <div v-if="!shown.length" class="mini">{{ t('no_results') }}</div>
      </div>
      <div class="row">
        <button v-if="peds.length > 1" class="ui-btn small ghost grow" @click="mix">{{ t('emote_mix') }}</button>
        <button class="ui-btn small ghost grow" @click="stop">{{ t('emote_stop') }}</button>
      </div>
      <span class="field-label">{{ t('emote_custom') }}</span>
      <div class="row">
        <input v-model="dict" class="cine-input" :placeholder="t('anim_dict')" />
        <input v-model="clip" class="cine-input" :placeholder="t('anim_clip')" />
      </div>
      <button class="ui-btn small ghost" :disabled="!dict || !clip" @click="playCustom">{{ t('play_anim') }}</button>
    </div>
  </div>
</template>
