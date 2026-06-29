import type { Pane, Project, Session } from '../types'
import { useStore } from '../store'
import { GHOSTTY_THEMES, DEFAULT_GHOSTTY_THEME } from '../theme/ghostty-themes'
import { AgentIcon, PlusIcon, SplitRightIcon, SplitDownIcon } from '../lib/icons'
import { TerminalPane } from './TerminalPane'
import { MessageInput } from './MessageInput'

function Cell({
  session,
  project,
  pane,
  focused,
  themeKey,
}: {
  session: Session
  project: Project
  pane: Pane
  focused: boolean
  themeKey: string
}) {
  const setActivePane = useStore((s) => s.setActivePane)
  const isShell = pane.kind === 'shell'
  const theme = (GHOSTTY_THEMES[themeKey] || GHOSTTY_THEMES[DEFAULT_GHOSTTY_THEME]).theme
  return (
    <div className={'term-cell' + (focused ? ' focused' : '')} onMouseDown={() => setActivePane(session.id, pane.id)}>
      <div className="term-cell-label">{pane.title}</div>
      <TerminalPane
        key={`${pane.id}:${themeKey}`}
        sid={pane.id}
        agent={isShell ? 'shell' : session.agent}
        cwd={project.path}
        yolo={session.yolo}
        focused={focused}
        theme={theme}
        sessionId={session.id}
        reportStatus={!isShell}
      />
    </div>
  )
}

export function TerminalWorkspace({ session, project }: { session: Session; project: Project }) {
  const setActivePane = useStore((s) => s.setActivePane)
  const closePane = useStore((s) => s.closePane)
  const addPane = useStore((s) => s.addPane)
  const splitSession = useStore((s) => s.splitSession)
  const themeKey = useStore((s) => s.appearanceSettings.ghosttyTheme)

  const activePane = session.panes.find((p) => p.id === session.activePaneId) || session.panes[0]
  const cells = session.splitLayout ? session.panes.slice(0, 2) : [activePane]

  return (
    <div className="term-workspace">
      <div className="term-tabs">
        <div className="term-tab-list">
          {session.panes.map((pane) => (
            <button
              key={pane.id}
              className={'term-tab' + (pane.id === session.activePaneId ? ' active' : '')}
              onClick={() => setActivePane(session.id, pane.id)}
            >
              <span className="tab-ico">
                <AgentIcon agent={pane.kind === 'shell' ? 'shell' : session.agent} size={12} />
              </span>
              <span className="tab-title">{pane.title}</span>
              {session.panes.length > 1 && (
                <span
                  className="tab-close"
                  onClick={(e) => {
                    e.stopPropagation()
                    closePane(session.id, pane.id)
                  }}
                >
                  ×
                </span>
              )}
            </button>
          ))}
        </div>
        <div className="term-tab-actions">
          <button title="Split right (⌘D)" aria-label="Split right" onClick={() => splitSession(session.id, 'right')}>
            <SplitRightIcon />
          </button>
          <button title="Split down (⌘⇧D)" aria-label="Split down" onClick={() => splitSession(session.id, 'down')}>
            <SplitDownIcon />
          </button>
          <button title="New tab (⌘T)" aria-label="New tab" onClick={() => addPane(session.id, 'shell')}>
            <PlusIcon />
          </button>
        </div>
      </div>

      <div className={'term-split-grid' + (session.splitLayout ? ' ' + session.splitLayout : '')}>
        {cells.map((pane) => (
          <Cell
            key={pane.id}
            session={session}
            project={project}
            pane={pane}
            focused={pane.id === session.activePaneId}
            themeKey={themeKey}
          />
        ))}
      </div>

      <MessageInput session={session} pane={activePane} />
    </div>
  )
}
