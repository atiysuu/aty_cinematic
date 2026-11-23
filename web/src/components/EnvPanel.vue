<script setup>
import { useSession } from '@/stores/session'
import { fetchNui, sendThrottled } from '@/utils/nui'
import { t } from '@/locale'
import EnvFields from './EnvFields.vue'

const session = useSession()

function set(field, value) {
  session.envLive = { ...session.envLive, [field]: value }
  sendThrottled('env_' + field, 'envSet', { patch: { [field]: value } })
}
function clear(field) {
  const next = { ...session.envLive }
  delete next[field]
  session.envLive = next
  fetchNui('envSet', { clear: [field] })
}
function addEnvKey() {
  const ph = session.playhead.t
  fetchNui('keyAdd', { shotId: session.state.shotId, t: session.state.scrub || session.state.playing ? ph : undefined, env: true })
}
</script>

<template>
  <div class="p-body">
    <div class="blk">
      <div class="blk-head">{{ t('env_live') }}</div>
      <span class="mini">{{ t('env_live_hint') }}</span>
      <button class="ui-btn small accent" @click="addEnvKey">{{ t('env_add_key') }}</button>
    </div>
    <EnvFields :env="session.envLive" @set="set" @clear="clear" />
  </div>
</template>
