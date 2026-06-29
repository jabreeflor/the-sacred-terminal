import { useEffect, useRef } from 'react'
import { ghosttyReady, Terminal, FitAddon, CATPPUCCIN_FRAPPE, type ITheme } from '../lib/ghostty'
import { registerPane } from '../lib/paneRegistry'
import { useStore } from '../store'

export type TerminalPaneProps = {
  /** Stable session/pane id — also the PTY host's key (one real pty per pane). */
  sid: string
  agent: string
  cwd: string
  yolo?: boolean
  focused?: boolean
  theme?: ITheme
  /** When the session id this pane belongs to, used to drive live status from output. */
  sessionId?: string
  reportStatus?: boolean
  onMeta?: (meta: { pid?: number; file?: string; reattached?: boolean }) => void
}

const wsProto = () => (location.protocol === 'https:' ? 'wss' : 'ws')

export function TerminalPane({ sid, agent, cwd, yolo, focused, theme, sessionId, reportStatus, onMeta }: TerminalPaneProps) {
  const hostRef = useRef<HTMLDivElement>(null)
  const termRef = useRef<Terminal | null>(null)

  useEffect(() => {
    let disposed = false
    let ws: WebSocket | null = null
    let fit: FitAddon | null = null
    let settleTimer: ReturnType<typeof setTimeout> | undefined
    const disposers: Array<() => void> = []

    ;(async () => {
      await ghosttyReady()
      if (disposed || !hostRef.current) return

      const term = new Terminal({
        fontSize: 13,
        fontFamily: "'JetBrains Mono', 'SF Mono', ui-monospace, Menlo, monospace",
        theme: theme ?? CATPPUCCIN_FRAPPE,
        cursorBlink: true,
        scrollback: 8000,
      })
      termRef.current = term
      fit = new FitAddon()
      term.loadAddon(fit)
      term.open(hostRef.current)
      try {
        fit.fit()
      } catch {
        /* not measured yet */
      }
      const dims = fit.proposeDimensions() || { cols: 80, rows: 24 }

      const params = new URLSearchParams({
        sid,
        agent,
        cwd,
        yolo: yolo ? '1' : '0',
        cols: String(dims.cols),
        rows: String(dims.rows),
      })
      ws = new WebSocket(`${wsProto()}://${location.host}/pty?${params.toString()}`)

      ws.onmessage = (e) => {
        const data = e.data
        if (typeof data === 'string') {
          if (data.startsWith('\x00META')) {
            try {
              onMeta?.(JSON.parse(data.slice(5)))
            } catch {
              /* ignore */
            }
            return
          }
          term.write(data)
        } else if (data instanceof ArrayBuffer) {
          term.write(new Uint8Array(data))
        }
        // Live status: output means the agent is working; settle to done.
        if (reportStatus && sessionId) {
          const { setStatus } = useStore.getState()
          setStatus(sessionId, 'working')
          clearTimeout(settleTimer)
          settleTimer = setTimeout(() => setStatus(sessionId, 'done'), 1400)
        }
      }

      const send = (d: string) => {
        if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ t: 'i', d }))
      }
      const dataDisp = term.onData(send)
      const resizeDisp = term.onResize(({ cols, rows }) => {
        if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ t: 'r', c: cols, r: rows }))
      })
      const unregister = registerPane(sid, { send, focus: () => term.focus() })
      disposers.push(() => dataDisp.dispose(), () => resizeDisp.dispose(), unregister)

      fit.observeResize()
      if (focused) term.focus()
    })()

    return () => {
      disposed = true
      clearTimeout(settleTimer)
      disposers.forEach((d) => d())
      try {
        ws?.close()
      } catch {
        /* ignore */
      }
      fit?.dispose()
      termRef.current?.dispose()
      termRef.current = null
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sid])

  useEffect(() => {
    if (focused) termRef.current?.focus()
  }, [focused])

  return <div ref={hostRef} className="term-host" onMouseDown={() => termRef.current?.focus()} />
}
