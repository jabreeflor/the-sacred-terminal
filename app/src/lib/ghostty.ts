// Thin wrapper around ghostty-web (libghostty's VT engine compiled to WASM).
// One shared WASM instance is initialized lazily and reused by every pane —
// the same battle-tested terminal core that runs the native Ghostty app.
import { init, Terminal, FitAddon, type ITheme, type ITerminalOptions } from 'ghostty-web'

let ready: Promise<void> | null = null

/** Initialize the Ghostty WASM engine exactly once. */
export function ghosttyReady(): Promise<void> {
  if (!ready) ready = init()
  return ready
}

// Ghostty's default theme — Catppuccin Frappé — imported verbatim (spec §9).
// Swapping this object re-skins every terminal pane at once.
export const CATPPUCCIN_FRAPPE: ITheme = {
  background: '#303446',
  foreground: '#c6d0f5',
  cursor: '#f2d5cf',
  cursorAccent: '#303446',
  selectionBackground: '#626880',
  selectionForeground: '#c6d0f5',
  black: '#51576d',
  red: '#e78284',
  green: '#a6d189',
  yellow: '#e5c890',
  blue: '#8caaee',
  magenta: '#f4b8e4',
  cyan: '#81c8be',
  white: '#a5adce',
  brightBlack: '#626880',
  brightRed: '#e67172',
  brightGreen: '#8ec772',
  brightYellow: '#d9ba73',
  brightBlue: '#7b9ef0',
  brightMagenta: '#f2a4db',
  brightCyan: '#5abfb5',
  brightWhite: '#b5bfe2',
}

export { Terminal, FitAddon }
export type { ITheme, ITerminalOptions }
