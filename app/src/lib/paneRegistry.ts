// Lets non-terminal UI (the message bar, keyboard shortcuts) talk to a live
// PTY: each mounted TerminalPane registers an imperative handle keyed by its
// pane id (== the PTY session id).
export interface PaneHandle {
  /** Write raw input to the pty (as if typed). */
  send: (data: string) => void
  /** Focus the terminal so keystrokes go to it. */
  focus: () => void
}

const registry = new Map<string, PaneHandle>()

export function registerPane(sid: string, handle: PaneHandle) {
  registry.set(sid, handle)
  return () => {
    if (registry.get(sid) === handle) registry.delete(sid)
  }
}

export function getPane(sid: string): PaneHandle | undefined {
  return registry.get(sid)
}
