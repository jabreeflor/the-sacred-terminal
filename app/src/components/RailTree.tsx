import type { MouseEvent } from 'react'
import { useStore } from '../store'
import { useUi } from '../ui'
import { AGENTS } from '../lib/agents'
import { statusMeta } from '../lib/status'
import { AgentIcon, SessionIcon, FolderIcon, PlusIcon, DragHandle, GearIcon } from '../lib/icons'

function anchorOf(e: MouseEvent) {
  const r = (e.currentTarget as HTMLElement).getBoundingClientRect()
  return { left: r.left, top: r.top, bottom: r.bottom, right: r.right, width: r.width }
}

export function RailTree() {
  const projects = useStore((s) => s.projects)
  const activeId = useStore((s) => s.activeId)
  const pinnedAgents = useStore((s) => s.pinnedAgents)
  const agentEnabled = useStore((s) => s.agentEnabled)
  const toggleCollapse = useStore((s) => s.toggleCollapse)
  const setActive = useStore((s) => s.setActive)
  const createSession = useStore((s) => s.createSession)
  const closeSession = useStore((s) => s.closeSession)
  const openSettings = useUi((s) => s.openSettings)
  const openPicker = useUi((s) => s.openPicker)
  const openProjectMenu = useUi((s) => s.openProjectMenu)

  const barAgents = pinnedAgents.filter((k) => agentEnabled[k])

  let kbd = 0
  return (
    <aside className="rail">
      <div className="rail-top">
        <button className="icon-btn" title="Settings" onClick={() => openSettings('agents')}>
          <GearIcon />
        </button>
        <button className="icon-btn" title="Import or create project" onClick={(e) => openProjectMenu(anchorOf(e))}>
          <PlusIcon size={15} />
        </button>
      </div>

      <div className="tree">
        {projects.map((p) => (
          <div key={p.id} className={'project' + (p.collapsed ? ' collapsed' : '')}>
            <div className="project-row" onClick={() => toggleCollapse(p.id)}>
              <span className="folder">
                <FolderIcon open={!p.collapsed} />
              </span>
              <span className="pname">{p.name}</span>
              <div className="agent-bar" onClick={(e) => e.stopPropagation()}>
                {barAgents.map((key) => (
                  <button key={key} title={'Pre-open ' + AGENTS[key].name} onClick={() => createSession(p.id, key, false)}>
                    <AgentIcon agent={key} size={14} />
                  </button>
                ))}
                <button title="More agents…" onClick={(e) => openPicker(p.id, anchorOf(e))}>
                  <PlusIcon size={13} />
                </button>
              </div>
            </div>

            {!p.collapsed && (
              <div className="sessions">
                {p.sessions.map((s) => {
                  kbd++
                  const meta = statusMeta(s.status)
                  const n = kbd
                  return (
                    <div
                      key={s.id}
                      className={'session' + (s.id === activeId ? ' active' : '')}
                      onClick={() => setActive(s.id)}
                    >
                      <span className="s-handle">
                        <DragHandle />
                      </span>
                      <span className="s-icon">
                        <SessionIcon agent={s.agent} status={s.status} size={13} />
                      </span>
                      <span className="s-label">{s.task}</span>
                      <span className="s-meta">
                        <span
                          className={'s-status-dot' + (meta.pulse ? ' pulse' : '')}
                          style={{ background: meta.color }}
                          title={meta.label}
                        />
                        <span className="s-kbd">⌘{n}</span>
                      </span>
                      <span
                        className="s-close"
                        title="Close session"
                        onClick={(e) => {
                          e.stopPropagation()
                          closeSession(s.id)
                        }}
                      >
                        ×
                      </span>
                    </div>
                  )
                })}
              </div>
            )}
          </div>
        ))}
      </div>
    </aside>
  )
}
