import { useStore } from '../store'
import { TerminalWorkspace } from './TerminalWorkspace'
import { IntegratedBrowser } from './IntegratedBrowser'
import { EmptyState } from './EmptyState'

export function Main() {
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
    <main className="main">
      {session && project ? (
        <div className={'workspace' + (session.browserOpen ? ' browser-open' : '')}>
          <TerminalWorkspace session={session} project={project} />
          {session.browserOpen && <IntegratedBrowser session={session} />}
        </div>
      ) : (
        <EmptyState />
      )}
    </main>
  )
}
