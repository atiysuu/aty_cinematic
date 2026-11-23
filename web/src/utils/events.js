// Lua -> NUI messages (always { action, data }).
import { useSession } from '@/stores/session'
import { useProject } from '@/stores/project'
import { useUi } from '@/stores/ui'
import { fetchNui } from './nui'
import { setLocale } from '@/locale'

export const initEvents = () => {
  const session = useSession()
  const project = useProject()
  const ui = useUi()
  let pickTimer = null

  window.addEventListener('message', (event) => {
    const msg = event.data
    if (!msg || typeof msg.action !== 'string') return
    const data = msg.data
    switch (msg.action) {
      case 'setup':
        if (data && data.locale) setLocale(data.locale)
        session.setup(data || {})
        if (data && data.config && data.config.letterbox) ui.letterboxOn = !!data.config.letterbox.enabled
        break
      case 'open':
        session.visible = true
        ui.reset()
        fetchNui('sessionAck') // the director is visible; Lua closes the session without this
        break
      case 'close':
        session.reset()
        project.setDoc(null)
        break
      case 'state':
        if (data) session.setState(data)
        break
      case 'cam':
        if (data) {
          // fields edited in the panel a moment ago keep the local value (the readout lags the drag)
          const now = performance.now()
          for (const f in session.camHold) {
            if (session.camHold[f] > now && session.cam && session.cam[f] !== undefined) data[f] = session.cam[f]
          }
          session.cam = data
        }
        break
      case 'project': {
        const had = !!project.doc
        project.setDoc(data || null)
        // Lua auto-opens the last project right after 'open': only ask for one if that does not land.
        if (!data) {
          clearTimeout(pickTimer)
          pickTimer = setTimeout(() => { if (session.visible && !project.doc) ui.projectsOpen = true }, 1500)
        } else if (!had) {
          clearTimeout(pickTimer)
          ui.projectsOpen = false
        }
        break
      }
      case 'projects':
        project.setProjects(data)
        break
      case 'playhead':
        if (data) session.playhead = data
        break
      case 'saveResult':
        session.saveResult = data || null
        break
      case 'env':
        session.envLive = data || {}
        break
      default:
        break
    }
  })
}
