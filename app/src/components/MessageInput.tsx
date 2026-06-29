import { useState } from 'react'
import type { Pane, Session } from '../types'
import { useStore } from '../store'
import { AGENTS } from '../lib/agents'
import { getPane } from '../lib/paneRegistry'
import { SessionIcon } from '../lib/icons'

// Writes a real line into the active pane's PTY (and flips the session to
// "working" for agent panes) — the spec's "input row" (§6), made real.
export function MessageInput({ session, pane }: { session: Session; pane: Pane }) {
  const sendToAgent = useStore((s) => s.sendToAgent)
  const [value, setValue] = useState('')
  const isShell = pane.kind === 'shell'

  const submit = () => {
    const msg = value.trim()
    if (!msg) return
    getPane(pane.id)?.send(msg + '\r')
    if (!isShell) sendToAgent(session.id, msg)
    setValue('')
  }

  return (
    <div className="term-input">
      <span className="ip">
        <SessionIcon agent={isShell ? 'shell' : session.agent} status={isShell ? 'idle' : session.status} size={14} />
      </span>
      <input
        value={value}
        placeholder={isShell ? 'type a command…' : `message ${AGENTS[session.agent].name}…`}
        onChange={(e) => setValue(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') submit()
        }}
      />
    </div>
  )
}
