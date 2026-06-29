import { useStore } from '../store'
import { SidebarIcon, GlobeIcon, BranchIcon } from '../lib/icons'

export function TitleBar() {
  const sidebarOpen = useStore((s) => s.sidebarOpen)
  const toggleRail = useStore((s) => s.toggleRail)
  const toggleBrowser = useStore((s) => s.toggleBrowser)
  const projects = useStore((s) => s.projects)
  const activeId = useStore((s) => s.activeId)

  let project = null
  let session = null
  for (const p of projects) {
    const s = p.sessions.find((x) => x.id === activeId)
    if (s) {
      project = p
      session = s
      break
    }
  }

  return (
    <div className="titlebar">
      <div className="traffic">
        <span className="light r" />
        <span className="light y" />
        <span className="light g" />
      </div>
      <button
        className={'icon-btn' + (sidebarOpen ? ' on' : '')}
        title="Toggle side rail (⌘B)"
        onClick={() => toggleRail()}
      >
        <SidebarIcon />
      </button>

      {session && project ? (
        <>
          <div className="title-crumb">
            <span className="proj-name">{project.name}</span>
            <span className="sep">›</span>
            <span className="sess-title">{session.task}</span>
          </div>
          <div className="title-actions">
            <button
              className={'term-browser-btn' + (session.browserOpen ? ' on' : '')}
              title="Toggle browser (⌘⌥B)"
              onClick={() => toggleBrowser()}
            >
              <GlobeIcon />
            </button>
            <span className="branch">
              <BranchIcon /> main
            </span>
          </div>
        </>
      ) : (
        <div className="title-session" />
      )}
    </div>
  )
}
