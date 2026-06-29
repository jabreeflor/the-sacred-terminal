import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import { immer } from 'zustand/middleware/immer'
import type {
  AgentKey,
  AppState,
  AppearanceSettings,
  GitSettings,
  Pane,
  Project,
  Session,
  SplitLayout,
  Status,
} from './types'
import { AGENTS, AGENT_KEYS, DEFAULT_PINNED_AGENTS, MAX_PINNED_AGENTS } from './lib/agents'
import { DEFAULT_GHOSTTY_THEME } from './theme/ghostty-themes'

let _uid = 1
const nid = () => `s${_uid++}`

function newPane(agent: AgentKey): Pane {
  return { id: nid(), title: AGENTS[agent]?.name ?? 'Shell', kind: agent === 'shell' ? 'shell' : 'agent' }
}

function makeSession(agent: AgentKey, task: string, partial: Partial<Session> = {}): Session {
  const pane = newPane(agent)
  return {
    id: nid(),
    agent,
    task,
    status: agent === 'shell' ? 'idle' : 'working',
    browserOpen: false,
    browserUrl: 'http://localhost:5173',
    panes: [pane],
    activePaneId: pane.id,
    splitLayout: null,
    ...partial,
  }
}

// Seed projects point at REAL directories so every session opens a real shell.
function seedProjects(): Project[] {
  return [
    {
      id: 'p0',
      name: 'the-sacred-terminal',
      path: '/home/user/the-sacred-terminal',
      collapsed: false,
      sessions: [
        makeSession('claude', 'Implement the spec on top of Ghostty', { status: 'working' }),
        makeSession('shell', 'zsh', { status: 'idle' }),
      ],
    },
    {
      id: 'p1',
      name: 'app',
      path: '/home/user/the-sacred-terminal/app',
      collapsed: false,
      sessions: [
        makeSession('codex', 'Wire node-pty bridge to ghostty-web', { status: 'waiting' }),
        makeSession('gemini', 'Tighten the rail spacing', { status: 'done', browserOpen: true, browserUrl: '/preview.html?p=marketing-site' }),
      ],
    },
    {
      id: 'p2',
      name: 'docs',
      path: '/home/user/the-sacred-terminal/docs',
      collapsed: false,
      sessions: [makeSession('cursor', 'Audit Spec.md vs implementation', { status: 'idle' })],
    },
    {
      id: 'p3',
      name: 'home',
      path: '/home/user',
      collapsed: true,
      sessions: [makeSession('shell', 'zsh', { status: 'idle' })],
    },
  ]
}

function defaultAgentEnabled(): Record<AgentKey, boolean> {
  return AGENT_KEYS.reduce(
    (acc, k) => {
      acc[k] = true
      return acc
    },
    {} as Record<AgentKey, boolean>,
  )
}

function defaultAppearance(): AppearanceSettings {
  return {
    railBg: '#0a0a0c',
    railFg: '#e6e6ea',
    railWidth: 'default',
    sessionHighlight: '#fab387',
    ghosttyTheme: DEFAULT_GHOSTTY_THEME,
  }
}

function defaultGit(): GitSettings {
  return {
    branchPrefix: 'git',
    customPrefix: '',
    keepMainUpdated: false,
    scGroupOrder: 'changes',
    autoRenameBranch: true,
    commitAttribution: false,
    showScAiActions: true,
    customCommand: '',
    draftPrByDefault: false,
    usePrTemplate: true,
    generatePrOnOpen: false,
    openPrAfterCreate: false,
  }
}

function ensureSessionPanes(s: Session) {
  if (!s.panes || s.panes.length === 0) {
    const p = newPane(s.agent)
    s.panes = [p]
    s.activePaneId = p.id
  }
  if (!s.activePaneId || !s.panes.some((p) => p.id === s.activePaneId)) {
    s.activePaneId = s.panes[0].id
  }
  if (s.splitLayout !== 'hsplit' && s.splitLayout !== 'vsplit') s.splitLayout = null
  if (s.panes.length < 2) s.splitLayout = null
}

export interface StoreActions {
  // rail / navigation
  toggleRail: (force?: boolean) => void
  setActive: (id: string) => void
  toggleCollapse: (projectId: string) => void
  // projects
  addProject: (name: string, path: string) => void
  // sessions
  createSession: (projectId: string, agent: AgentKey, worktree?: boolean) => void
  closeSession: (sessionId: string) => void
  setStatus: (sessionId: string, status: Status) => void
  sendToAgent: (sessionId: string, message: string) => void
  // panes (tabs + splits)
  addPane: (sessionId: string, kind?: 'agent' | 'shell') => void
  splitSession: (sessionId: string, direction: 'right' | 'down') => void
  closePane: (sessionId: string, paneId: string) => void
  setActivePane: (sessionId: string, paneId: string) => void
  // integrated browser
  toggleBrowser: (sessionId?: string, force?: boolean) => void
  setBrowserUrl: (sessionId: string, url: string) => void
  // settings
  setAgentEnabled: (key: AgentKey, enabled: boolean) => void
  togglePin: (key: AgentKey) => void
  setOpenWithYolo: (on: boolean) => void
  setGit: <K extends keyof GitSettings>(key: K, value: GitSettings[K]) => void
  setAppearance: <K extends keyof AppearanceSettings>(key: K, value: AppearanceSettings[K]) => void
}

export type Store = AppState & StoreActions

function findSessionMut(state: AppState, id: string): { project: Project; session: Session } | null {
  for (const project of state.projects) {
    const session = project.sessions.find((s) => s.id === id)
    if (session) return { project, session }
  }
  return null
}

export const useStore = create<Store>()(
  persist(
    immer((set, get) => ({
      sidebarOpen: true,
      activeId: null,
      projects: seedProjects(),
      agentEnabled: defaultAgentEnabled(),
      pinnedAgents: DEFAULT_PINNED_AGENTS.slice(),
      agentSettings: { openWithYolo: true },
      appearanceSettings: defaultAppearance(),
      gitSettings: defaultGit(),

      toggleRail: (force) =>
        set((s) => {
          s.sidebarOpen = force ?? !s.sidebarOpen
        }),

      setActive: (id) =>
        set((s) => {
          s.activeId = id
        }),

      toggleCollapse: (projectId) =>
        set((s) => {
          const p = s.projects.find((x) => x.id === projectId)
          if (p) p.collapsed = !p.collapsed
        }),

      addProject: (name, path) =>
        set((s) => {
          const cleanName = name.trim() || path.trim().split('/').filter(Boolean).pop() || 'untitled'
          s.projects.push({ id: nid(), name: cleanName, path: path.trim() || `~/${cleanName}`, collapsed: false, sessions: [] })
        }),

      createSession: (projectId, agent, worktree) =>
        set((s) => {
          const p = s.projects.find((x) => x.id === projectId)
          if (!p) return
          const a = AGENTS[agent]
          const yolo = s.agentSettings.openWithYolo && !!a.yolo
          const session = makeSession(agent, agent === 'shell' ? 'zsh' : `New ${a.name} session`, {
            worktree: !!worktree,
            yolo,
            browserUrl: 'http://localhost:5173',
          })
          p.sessions.push(session)
          p.collapsed = false
          s.activeId = session.id
        }),

      closeSession: (sessionId) =>
        set((s) => {
          for (const p of s.projects) {
            const idx = p.sessions.findIndex((x) => x.id === sessionId)
            if (idx !== -1) {
              p.sessions.splice(idx, 1)
              break
            }
          }
          if (s.activeId === sessionId) {
            const all = s.projects.flatMap((p) => p.sessions)
            s.activeId = all[0]?.id ?? null
          }
        }),

      setStatus: (sessionId, status) =>
        set((s) => {
          const found = findSessionMut(s, sessionId)
          if (found) found.session.status = status
        }),

      sendToAgent: (sessionId, message) =>
        set((s) => {
          const found = findSessionMut(s, sessionId)
          if (!found) return
          found.session.status = 'working'
          if (message.trim()) found.session.task = message.trim()
        }),

      addPane: (sessionId, kind = 'shell') =>
        set((s) => {
          const found = findSessionMut(s, sessionId)
          if (!found) return
          const { session } = found
          ensureSessionPanes(session)
          const pane: Pane = { id: nid(), title: kind === 'shell' ? 'shell' : AGENTS[session.agent].name, kind }
          session.panes.push(pane)
          session.activePaneId = pane.id
          session.splitLayout = null
        }),

      splitSession: (sessionId, direction) =>
        set((s) => {
          const found = findSessionMut(s, sessionId)
          if (!found) return
          const { session } = found
          ensureSessionPanes(session)
          if (session.panes.length < 2) {
            const pane: Pane = { id: nid(), title: direction === 'down' ? 'shell' : 'shell', kind: 'shell' }
            session.panes.push(pane)
          }
          session.splitLayout = direction === 'down' ? 'vsplit' : 'hsplit'
          session.activePaneId = session.panes[session.panes.length - 1].id
        }),

      closePane: (sessionId, paneId) =>
        set((s) => {
          const found = findSessionMut(s, sessionId)
          if (!found) return
          const { session } = found
          if (session.panes.length <= 1) return
          session.panes = session.panes.filter((p) => p.id !== paneId)
          if (session.activePaneId === paneId) session.activePaneId = session.panes[0].id
          if (session.panes.length < 2) session.splitLayout = null
        }),

      setActivePane: (sessionId, paneId) =>
        set((s) => {
          const found = findSessionMut(s, sessionId)
          if (found && found.session.panes.some((p) => p.id === paneId)) found.session.activePaneId = paneId
        }),

      toggleBrowser: (sessionId, force) =>
        set((s) => {
          const id = sessionId ?? s.activeId
          if (!id) return
          const found = findSessionMut(s, id)
          if (found) found.session.browserOpen = force ?? !found.session.browserOpen
        }),

      setBrowserUrl: (sessionId, url) =>
        set((s) => {
          const found = findSessionMut(s, sessionId)
          if (found) found.session.browserUrl = url.trim() || found.session.browserUrl
        }),

      setAgentEnabled: (key, enabled) =>
        set((s) => {
          const enabledKeys = AGENT_KEYS.filter((k) => s.agentEnabled[k])
          if (!enabled && s.agentEnabled[key] && enabledKeys.length <= 1) return
          s.agentEnabled[key] = enabled
          if (!enabled) s.pinnedAgents = s.pinnedAgents.filter((k) => k !== key)
        }),

      togglePin: (key) =>
        set((s) => {
          if (!s.agentEnabled[key]) return
          const idx = s.pinnedAgents.indexOf(key)
          if (idx !== -1) s.pinnedAgents.splice(idx, 1)
          else if (s.pinnedAgents.length < MAX_PINNED_AGENTS) s.pinnedAgents.push(key)
        }),

      setOpenWithYolo: (on) =>
        set((s) => {
          s.agentSettings.openWithYolo = on
        }),

      setGit: (key, value) =>
        set((s) => {
          ;(s.gitSettings as GitSettings)[key] = value
        }),

      setAppearance: (key, value) =>
        set((s) => {
          ;(s.appearanceSettings as AppearanceSettings)[key] = value
        }),
    })),
    {
      name: 'sacred-terminal.v1',
      version: 1,
      onRehydrateStorage: () => (state) => {
        if (!state) return
        // keep the uid counter ahead of any persisted ids
        let max = 0
        for (const p of state.projects) {
          for (const s of p.sessions) {
            ensureSessionPanes(s)
            for (const id of [s.id, ...s.panes.map((x) => x.id)]) {
              const n = Number(String(id).replace(/\D/g, ''))
              if (Number.isFinite(n)) max = Math.max(max, n)
            }
          }
        }
        _uid = max + 1
        if (!state.activeId) {
          state.activeId = state.projects.flatMap((p) => p.sessions)[0]?.id ?? null
        }
      },
    },
  ),
)

// Non-reactive helper for imperative reads.
export function findSession(id: string | null) {
  if (!id) return null
  return findSessionMut(useStore.getState(), id)
}

export type { SplitLayout }
