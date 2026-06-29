import type { MouseEvent } from 'react'
import { useStore } from '../store'
import { useUi } from '../ui'
import { AgentIcon } from '../lib/icons'

export function EmptyState() {
  const projects = useStore((s) => s.projects)
  const openPicker = useUi((s) => s.openPicker)

  const onNew = (e: MouseEvent) => {
    const p = projects[0]
    if (!p) return
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect()
    openPicker(p.id, { left: r.left, top: r.top, bottom: r.bottom, right: r.right, width: r.width })
  }

  return (
    <div className="empty">
      <div className="ghost-art">
        <AgentIcon agent="claude" size={28} />
      </div>
      <div className="big">No session open</div>
      <div>Hover a project and pick an agent, or press ⌘N.</div>
      <div className="pill" onClick={onNew}>
        + New session
      </div>
    </div>
  )
}
