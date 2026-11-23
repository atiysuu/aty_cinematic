// NUI bridge helpers. No success mock as fallback: a failed call is reported as { ok: false }
// (bug-lessons: a mock masks a missing server bridge as fake success).
const resourceName =
  typeof window !== 'undefined' && window.GetParentResourceName
    ? window.GetParentResourceName()
    : 'aty_cinematic'

export const fetchNui = async (event, data = {}) => {
  try {
    const res = await fetch(`https://${resourceName}/${event}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    })
    if (!res.ok) return { ok: false, reason: `http_${res.status}` }
    const text = await res.text()
    if (!text) return { ok: true }
    try {
      return JSON.parse(text)
    } catch {
      return { ok: false, reason: 'bad_json' }
    }
  } catch {
    return { ok: false, reason: 'no_answer' }
  }
}

// Leading + trailing throttle per key (slider drags). The last value always goes out.
const timers = new Map()
export const sendThrottled = (key, event, data, ms = 60) => {
  const st = timers.get(key) || { last: 0, timer: null, pending: null }
  timers.set(key, st)
  const fire = (payload) => {
    st.last = performance.now()
    st.pending = null
    fetchNui(event, payload)
  }
  const wait = ms - (performance.now() - st.last)
  if (wait <= 0) {
    if (st.timer) { clearTimeout(st.timer); st.timer = null }
    fire(data)
    return
  }
  st.pending = data
  if (!st.timer) {
    st.timer = setTimeout(() => {
      st.timer = null
      if (st.pending) fire(st.pending)
    }, wait)
  }
}

let pointerOverUi = false
export const initPointerTracking = () => {
  window.addEventListener(
    'mousemove',
    (e) => {
      const el = e.target
      const over = !!(el && el.closest && el.closest('.ui-blocking'))
      if (over !== pointerOverUi) {
        pointerOverUi = over
        fetchNui('pointerOver', { over })
      }
    },
    { passive: true },
  )
  // Text fields: the game must stop receiving keys while one has focus.
  const isText = (el) => el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') && el.type !== 'range' && el.type !== 'checkbox'
  window.addEventListener('focusin', (e) => { if (isText(e.target)) fetchNui('inputFocus', { on: true }) })
  window.addEventListener('focusout', (e) => { if (isText(e.target)) fetchNui('inputFocus', { on: false }) })
}
