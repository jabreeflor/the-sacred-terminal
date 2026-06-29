import type { AgentKey } from '../types'

export interface AgentDef {
  name: string
  sub: string
  /** Base launch command (resolved on the server). */
  cmd: string
  /** Permission-bypass flag appended when YOLO mode is on (spec §7). */
  yolo: string | null
  /** Brand icon basename in /icons. */
  icon: string
}

// Roster — mirrors spec §7. Brand SVGs are vendored from Lobe Icons.
export const AGENTS: Record<AgentKey, AgentDef> = {
  claude: { name: 'Claude Code', sub: 'Anthropic · Opus 4.8', cmd: 'claude', yolo: '--dangerously-skip-permissions', icon: 'claude-color.svg' },
  codex: { name: 'Codex', sub: 'OpenAI · gpt-5', cmd: 'codex', yolo: '--dangerously-bypass-approvals-and-sandbox', icon: 'openai-color.svg' },
  cursor: { name: 'Cursor Agent', sub: 'Cursor CLI', cmd: 'cursor-agent', yolo: '--yolo', icon: 'cursor-color.svg' },
  gemini: { name: 'Gemini', sub: 'Google · 2.5 Pro', cmd: 'gemini', yolo: '--yolo', icon: 'gemini-color.svg' },
  copilot: { name: 'Copilot', sub: 'GitHub', cmd: 'copilot', yolo: null, icon: 'copilot-color.svg' },
  opencode: { name: 'OpenCode', sub: 'open source', cmd: 'opencode', yolo: null, icon: 'cline-color.svg' },
  shell: { name: 'Shell', sub: 'zsh', cmd: 'zsh', yolo: null, icon: 'shell-color.svg' },
}

export const AGENT_KEYS = Object.keys(AGENTS) as AgentKey[]

export const MAX_PINNED_AGENTS = 6
export const DEFAULT_PINNED_AGENTS: AgentKey[] = ['opencode', 'cursor', 'gemini', 'codex', 'claude']

/** Command preview string for the settings list / command-preview (spec §7). */
export function agentLaunchCmd(key: AgentKey, yolo: boolean): string {
  const a = AGENTS[key]
  if (!a) return ''
  if (yolo && a.yolo) return `${a.cmd} ${a.yolo}`
  return a.cmd
}

export function agentIconSrc(key: AgentKey): string {
  return `/icons/${AGENTS[key]?.icon || 'shell-color.svg'}`
}
