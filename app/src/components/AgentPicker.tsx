import { useStore } from '../store'
import { useUi } from '../ui'
import { AGENTS, AGENT_KEYS } from '../lib/agents'
import { AgentIcon } from '../lib/icons'

export function AgentPicker() {
  const pickerOpen = useUi((s) => s.pickerOpen)
  const projectId = useUi((s) => s.pickerProjectId)
  const anchor = useUi((s) => s.pickerAnchor)
  const worktree = useUi((s) => s.pickerWorktree)
  const setWorktree = useUi((s) => s.setPickerWorktree)
  const closePicker = useUi((s) => s.closePicker)
  const agentEnabled = useStore((s) => s.agentEnabled)
  const createSession = useStore((s) => s.createSession)

  if (!pickerOpen) return null

  const left = anchor ? Math.min(anchor.left, window.innerWidth - 380) : 80
  const top = anchor ? Math.min(anchor.bottom + 6, window.innerHeight - 420) : 80

  return (
    <>
      <div className="scrim" onClick={closePicker} />
      <div className="picker" style={{ left, top }}>
        <div className="ph">Pre-open a session with…</div>
        <div
          className={'picker-worktree' + (worktree ? ' on' : '')}
          onClick={() => setWorktree(!worktree)}
        >
          <span className="box">
            <svg width="11" height="11" viewBox="0 0 12 12">
              <path d="M2.5 6.2l2.4 2.4 4.6-5" fill="none" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </span>
          <span className="picker-worktree-label">Open with worktree</span>
        </div>
        <div>
          {AGENT_KEYS.filter((k) => agentEnabled[k]).map((key) => (
            <div
              key={key}
              className="agent"
              onClick={() => {
                if (projectId) createSession(projectId, key, worktree)
                closePicker()
              }}
            >
              <span className="ag-icon">
                <AgentIcon agent={key} size={20} />
              </span>
              <span className="ag-body">
                <div className="ag-name">{AGENTS[key].name}</div>
                <div className="ag-sub">{AGENTS[key].sub}</div>
              </span>
            </div>
          ))}
        </div>
      </div>
    </>
  )
}
