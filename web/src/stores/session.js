import { defineStore } from 'pinia'

export const useSession = defineStore('session', {
  state: () => ({
    visible: false,
    camHold: {}, // cam field -> performance.now() until which panel edits win over the Lua readout
    config: {
      fov: { min: 5, max: 130 },
      speed: { min: 0.25, max: 120 },
      dof: { enabled: true, defaults: { near: 0.5, far: 12, strength: 1 } },
      lights: { max: 32, defaults: {} },
      actors: { max: 12 },
      timeline: { maxKeys: 200, playheadHz: 20 },
      ratios: [2.39, 2.35, 2.0, 1.85, 1.333],
      weathers: [],
      timeScaleMin: 0.05,
      presets: { moves: [], moveGroups: [], looks: [], lookGroups: [], scenes: [], sceneGroups: [] },
    },
    keys: [],
    version: '',
    state: {
      mode: 'edit', rig: 'free', rigTarget: null, cursor: false, clean: false,
      playing: false, scrub: false, preloading: false, dirty: false, saving: false,
      shotId: null, projectId: null, gizmo: { active: false }, placer: false, speed: 6, smoothing: 0.2, inertia: 0.15, pathViz: false,
    },
    cam: {
      pos: [0, 0, 0], rot: [0, 0, 0], fov: 50, speed: 6,
      dof: { on: false, near: 0.5, far: 12, str: 1, target: null },
    },
    playhead: { t: 0, playing: false },
    envLive: {},
    saveResult: null,
  }),
  actions: {
    setup(data) {
      if (data.config) this.config = { ...this.config, ...data.config }
      this.keys = data.keys || []
      this.version = data.version || ''
    },
    setState(s) {
      this.state = { ...this.state, ...s }
    },
    reset() {
      this.visible = false
      this.playhead = { t: 0, playing: false }
      this.envLive = {}
      this.saveResult = null
    },
  },
})
