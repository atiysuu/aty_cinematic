import { defineStore } from 'pinia'

// Framing guides are a per-viewer convenience: kept in this browser, the page works without storage.
const GUIDES_KEY = 'aty_cinematic.guides'
const guideDefaults = () => ({
  on: false, // master switch
  inClean: true, // also in clean view (H), where the picture is unobstructed
  crop: 0, // 0 = off, else width / height of a crop frame (9:16 = 0.5625)
  mask: 0.6, // how dark the picture outside the crop frame is
  thirds: true, golden: false, cross: false, diagonals: false, safe: false,
  opacity: 0.3,
  level: false, info: false,
})
const loadGuides = () => {
  try {
    const saved = JSON.parse(localStorage.getItem(GUIDES_KEY) || '{}')
    return { ...guideDefaults(), ...(saved && typeof saved === 'object' ? saved : {}) }
  } catch (e) {
    return guideDefaults()
  }
}

export const useUi = defineStore('ui', {
  state: () => ({
    panel: 'camera', // camera | presets | actors | lights | env | framing
    selKeyId: null,
    selActorId: null, // the one picked last (rig target, focus)
    selActorIds: [], // everything picked in the Actors panel
    selLightId: null,
    projectsOpen: false,
    helpOpen: false,
    letterboxOn: false,
    guides: loadGuides(),
    presetTab: 'moves', // moves | scenes | looks
    presetTarget: '', // actor id the moves frame ('' = what the camera looks at)
    presetMove: null, // picked move / scene id (null = the first one)
    presetScene: null,
    lastLook: null,
    pxPerSec: 60,
  }),
  actions: {
    reset() {
      this.selKeyId = null
      this.selActorId = null
      this.selActorIds = []
      this.selLightId = null
      this.projectsOpen = false
      this.helpOpen = false
      this.presetTarget = ''
      this.lastLook = null
    },
    selectActors(ids) {
      this.selActorIds = [...ids]
      this.selActorId = ids.length ? ids[ids.length - 1] : null
    },
    saveGuides() {
      try { localStorage.setItem(GUIDES_KEY, JSON.stringify(this.guides)) } catch (e) { /* storage unavailable: this session only */ }
    },
  },
})
