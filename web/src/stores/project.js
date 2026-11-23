import { defineStore } from 'pinia'
import { useSession } from './session'

let lastEdit = 0
let pendingTimer = null

export const useProject = defineStore('project', {
  state: () => ({
    doc: null,
    projects: [],
    pending: null,
  }),
  getters: {
    shot(state) {
      const id = useSession().state.shotId
      return state.doc ? state.doc.shots.find((s) => s.id === id) || null : null
    },
    actors: (state) => (state.doc ? state.doc.actors : []),
    lights: (state) => (state.doc ? state.doc.lights : []),
    duration() {
      const s = this.shot
      if (!s || !s.keys.length) return 0
      return Math.max(...s.keys.map((k) => k.t + (k.hold || 0)))
    },
  },
  actions: {
    // Local optimistic edits stamp this, so an older echo from Lua does not overwrite a drag in progress.
    markEdit() {
      lastEdit = performance.now()
    },
    setDoc(doc) {
      const wait = 220 - (performance.now() - lastEdit)
      if (wait > 0) {
        this.pending = doc
        if (!pendingTimer) {
          pendingTimer = setTimeout(() => {
            pendingTimer = null
            if (this.pending !== null) { this.doc = this.pending; this.pending = null }
          }, wait)
        }
        return
      }
      this.pending = null
      this.doc = doc || null
    },
    setProjects(list) {
      this.projects = Array.isArray(list) ? list : []
    },
  },
})
