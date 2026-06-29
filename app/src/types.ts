// ============================================================
// The Sacred Terminal — core data model (spec §4)
// ============================================================

export type AgentKey =
  | 'claude'
  | 'codex'
  | 'cursor'
  | 'gemini'
  | 'copilot'
  | 'opencode'
  | 'shell'

/** Drives the rail's dot color, label and pulse (spec §8). */
export type Status = 'working' | 'waiting' | 'idle' | 'done'

export type SplitLayout = null | 'hsplit' | 'vsplit'

/** A tab inside a session — the session's agent or a shell. */
export interface Pane {
  /** Stable id — also the PTY host's session key (one real pty per pane). */
  id: string
  title: string
  kind: 'agent' | 'shell'
}

/** A terminal bound to one agent, with a status and a short task line. */
export interface Session {
  id: string
  agent: AgentKey
  task: string
  status: Status
  worktree?: boolean
  yolo?: boolean
  browserOpen: boolean
  browserUrl: string
  panes: Pane[]
  activePaneId: string
  splitLayout: SplitLayout
}

/** A folder on disk holding zero or more sessions. */
export interface Project {
  id: string
  name: string
  /** Absolute path used as the real cwd for this project's PTYs. */
  path: string
  collapsed: boolean
  sessions: Session[]
}

export interface AgentSettings {
  openWithYolo: boolean
}

export interface AppearanceSettings {
  railBg: string
  railFg: string
  railWidth: 'compact' | 'default' | 'wide'
  sessionHighlight: string
  ghosttyTheme: string
}

export interface GitSettings {
  branchPrefix: 'git' | 'custom' | 'none'
  customPrefix: string
  keepMainUpdated: boolean
  scGroupOrder: 'changes' | 'staged' | 'untracked'
  autoRenameBranch: boolean
  commitAttribution: boolean
  showScAiActions: boolean
  customCommand: string
  draftPrByDefault: boolean
  usePrTemplate: boolean
  generatePrOnOpen: boolean
  openPrAfterCreate: boolean
}

export interface AppState {
  sidebarOpen: boolean
  activeId: string | null
  projects: Project[]
  agentEnabled: Record<AgentKey, boolean>
  pinnedAgents: AgentKey[]
  agentSettings: AgentSettings
  appearanceSettings: AppearanceSettings
  gitSettings: GitSettings
}
