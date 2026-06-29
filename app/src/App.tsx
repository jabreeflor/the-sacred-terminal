import { useEffect } from 'react'
import { useStore, findSession } from './store'
import { useUi } from './ui'
import { applyAppearance } from './lib/appearance'
import { getPane } from './lib/paneRegistry'
import { TitleBar } from './components/TitleBar'
import { RailTree } from './components/RailTree'
import { Main } from './components/Main'
import { AgentPicker } from './components/AgentPicker'
import { ProjectDialogs } from './components/ProjectDialogs'
import { SettingsPanel } from './components/SettingsPanel'
import { Toast } from './components/Toast'

export function App() {
  const sidebarOpen = useStore((s) => s.sidebarOpen)
  const appearance = useStore((s) => s.appearanceSettings)

  // Apply rail/chrome theme to CSS variables.
  useEffect(() => {
    applyAppearance(appearance)
  }, [appearance])

  // Global keyboard shortcuts (spec §6).
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const store = useStore.getState()
      const ui = useUi.getState()
      const mod = e.metaKey || e.ctrlKey
      const k = e.key.toLowerCase()

      if (mod && k === 'b' && !e.altKey) {
        e.preventDefault()
        store.toggleRail()
      } else if (mod && e.altKey && k === 'b') {
        e.preventDefault()
        store.toggleBrowser()
      } else if (mod && k === 't') {
        e.preventDefault()
        if (store.activeId) store.addPane(store.activeId, 'shell')
      } else if (mod && k === 'd' && !e.shiftKey) {
        e.preventDefault()
        if (store.activeId) store.splitSession(store.activeId, 'right')
      } else if (mod && e.shiftKey && k === 'd') {
        e.preventDefault()
        if (store.activeId) store.splitSession(store.activeId, 'down')
      } else if (mod && k === 'w') {
        const found = findSession(store.activeId)
        if (found && found.session.panes.length > 1) {
          e.preventDefault()
          store.closePane(found.session.id, found.session.activePaneId)
        }
      } else if (mod && k === 'n') {
        e.preventDefault()
        const found = findSession(store.activeId)
        const p = found ? found.project : store.projects[0]
        if (p) {
          const el = document.querySelector('.rail-top') as HTMLElement | null
          const r = el?.getBoundingClientRect()
          ui.openPicker(p.id, r ? { left: r.left, top: r.top, bottom: r.bottom, right: r.right, width: r.width } : { left: 80, top: 60, bottom: 90, right: 200, width: 120 })
        }
      } else if (e.key === 'Escape') {
        ui.closeAll()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  // Keep the focused pane's terminal focused when the active session changes.
  const activeId = useStore((s) => s.activeId)
  useEffect(() => {
    const found = findSession(activeId)
    if (found) getPane(found.session.activePaneId)?.focus()
  }, [activeId])

  return (
    <div className={'app' + (sidebarOpen ? '' : ' rail-collapsed')}>
      <TitleBar />
      <div className="body">
        <RailTree />
        <Main />
      </div>
      <AgentPicker />
      <ProjectDialogs />
      <SettingsPanel />
      <Toast />
    </div>
  )
}
