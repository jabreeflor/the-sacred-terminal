import { useStore } from '../store'
import { useUi } from '../ui'
import { AGENT_KEYS, AGENTS, MAX_PINNED_AGENTS, agentLaunchCmd } from '../lib/agents'
import { GHOSTTY_THEMES } from '../theme/ghostty-themes'
import { AgentIcon, CloseIcon } from '../lib/icons'
import type { GitSettings } from '../types'

function Switch({ on, onClick, label }: { on: boolean; onClick: () => void; label: string }) {
  return <button type="button" className={'set-switch' + (on ? ' on' : '')} aria-label={label} onClick={onClick} />
}

function AgentsPane() {
  const agentEnabled = useStore((s) => s.agentEnabled)
  const pinnedAgents = useStore((s) => s.pinnedAgents)
  const openWithYolo = useStore((s) => s.agentSettings.openWithYolo)
  const setOpenWithYolo = useStore((s) => s.setOpenWithYolo)
  const setAgentEnabled = useStore((s) => s.setAgentEnabled)
  const togglePin = useStore((s) => s.togglePin)
  const pinned = pinnedAgents.length

  return (
    <div className="settings-pane">
      <p className="settings-pane-intro">Enable agents for pre-open sessions. Pin up to 6 for the project hover quick-select menu.</p>
      <div className="settings-meta">
        <span>
          Pinned <span className="badge">{pinned}/{MAX_PINNED_AGENTS}</span>
        </span>
        <span>
          Installed <span className="badge">{AGENT_KEYS.length} detected</span>
        </span>
      </div>
      <div className="settings-scroll">
        <div className="set-section">
          <div className="set-row">
            <div className="set-row-body">
              <div className="set-row-title">Open with YOLO mode</div>
              <div className="set-row-desc">
                When pre-opening an agent session, launch with permission bypass flags (<code>--yolo</code>,{' '}
                <code>--dangerously-skip-permissions</code>, etc.). Off uses each agent’s safe default command.
              </div>
            </div>
            <div className="set-row-ctrl">
              <Switch on={openWithYolo} onClick={() => setOpenWithYolo(!openWithYolo)} label="Open with YOLO mode" />
            </div>
          </div>
        </div>
        <div className="settings-list">
          {AGENT_KEYS.map((key) => {
            const on = agentEnabled[key]
            const pinOn = pinnedAgents.includes(key)
            const pinDisabled = !on || (!pinOn && pinned >= MAX_PINNED_AGENTS)
            return (
              <div key={key} className={'setting-agent' + (on ? '' : ' is-off')}>
                <div className="setting-agent-icon">
                  <AgentIcon agent={key} size={20} />
                </div>
                <div className="setting-agent-body">
                  <div className="setting-agent-title">
                    <span className="name">{AGENTS[key].name}</span>
                    <span className="pill">Detected</span>
                  </div>
                  <div className="setting-agent-cmd">{agentLaunchCmd(key, openWithYolo)}</div>
                </div>
                <div className="setting-agent-ctrls">
                  <button
                    type="button"
                    className={'pin-btn' + (pinOn ? ' on' : '')}
                    title={pinOn ? 'Unpin from quick select' : pinDisabled ? 'Maximum 6 pinned' : 'Pin for quick select'}
                    disabled={pinDisabled}
                    onClick={() => togglePin(key)}
                  >
                    <svg width="13" height="13" viewBox="0 0 24 24" fill={pinOn ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M12 17v5" />
                      <path d="M9 3h6l1 7H8l1-7z" />
                      <path d="M9 10v4l-3 3h12l-3-3v-4" />
                    </svg>
                  </button>
                  <div className="seg-toggle">
                    <button type="button" className={on ? 'on' : ''} onClick={() => setAgentEnabled(key, true)}>
                      Enabled
                    </button>
                    <button type="button" className={!on ? 'on-off' : ''} onClick={() => setAgentEnabled(key, false)}>
                      Disabled
                    </button>
                  </div>
                </div>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}

function Seg<K extends keyof GitSettings>({ name, options }: { name: K; options: Array<{ val: GitSettings[K]; label: string }> }) {
  const value = useStore((s) => s.gitSettings[name])
  const setGit = useStore((s) => s.setGit)
  return (
    <div className="set-seg">
      {options.map((o) => (
        <button key={String(o.val)} type="button" className={value === o.val ? 'on' : ''} onClick={() => setGit(name, o.val)}>
          {o.label}
        </button>
      ))}
    </div>
  )
}

function GitToggle({ name, label }: { name: keyof GitSettings; label: string }) {
  const value = useStore((s) => s.gitSettings[name]) as boolean
  const setGit = useStore((s) => s.setGit)
  return <Switch on={value} onClick={() => setGit(name, !value as never)} label={label} />
}

function GitCheck({ name, title, desc }: { name: keyof GitSettings; title: string; desc: string }) {
  const value = useStore((s) => s.gitSettings[name]) as boolean
  const setGit = useStore((s) => s.setGit)
  return (
    <div className="set-check-row">
      <input type="checkbox" checked={value} onChange={(e) => setGit(name, e.target.checked as never)} />
      <label onClick={() => setGit(name, !value as never)}>
        <div className="set-row-title">{title}</div>
        <div className="set-row-desc">{desc}</div>
      </label>
    </div>
  )
}

function GitPane() {
  const branchPrefix = useStore((s) => s.gitSettings.branchPrefix)
  const customPrefix = useStore((s) => s.gitSettings.customPrefix)
  const customCommand = useStore((s) => s.gitSettings.customCommand)
  const setGit = useStore((s) => s.setGit)

  return (
    <div className="settings-pane">
      <p className="settings-pane-intro">Branch naming, base refs, attribution, and Git AI author.</p>
      <div className="settings-scroll">
        <div className="set-section">
          <h3>Branch prefix</h3>
          <p className="set-desc">Choose whether branch names use your Git username, a custom prefix, or no prefix.</p>
          <Seg name="branchPrefix" options={[{ val: 'git', label: 'Git username' }, { val: 'custom', label: 'Custom' }, { val: 'none', label: 'None' }]} />
          {branchPrefix === 'custom' && (
            <input className="set-input" placeholder="feature" value={customPrefix} onChange={(e) => setGit('customPrefix', e.target.value)} />
          )}
        </div>

        <div className="set-section">
          <div className="set-row">
            <div className="set-row-body">
              <div className="set-row-title">Keep local main up to date</div>
              <div className="set-row-desc">When creating a workspace, refresh the remote base and fast-forward your local main or master if there are no uncommitted changes.</div>
            </div>
            <div className="set-row-ctrl"><GitToggle name="keepMainUpdated" label="Keep local main up to date" /></div>
          </div>
          <div className="set-row">
            <div className="set-row-body">
              <div className="set-row-title">Source control group order</div>
              <div className="set-row-desc">Choose whether Changes, Staged Changes, or Untracked Files appear first.</div>
            </div>
            <div className="set-row-ctrl">
              <Seg name="scGroupOrder" options={[{ val: 'changes', label: 'Changes first' }, { val: 'staged', label: 'Staged first' }, { val: 'untracked', label: 'Untracked first' }]} />
            </div>
          </div>
          <div className="set-row">
            <div className="set-row-body">
              <div className="set-row-title">Auto-rename branch</div>
              <div className="set-row-desc">When an agent starts in a new workspace, rename its auto-generated branch to a short name summarizing the task.</div>
            </div>
            <div className="set-row-ctrl"><GitToggle name="autoRenameBranch" label="Auto-rename branch" /></div>
          </div>
          <div className="set-row">
            <div className="set-row-body">
              <div className="set-row-title">Commit attribution</div>
              <div className="set-row-desc">Add attribution to commits, pull requests, and issues.</div>
            </div>
            <div className="set-row-ctrl"><GitToggle name="commitAttribution" label="Commit attribution" /></div>
          </div>
        </div>

        <div className="set-section">
          <h3>Source control AI</h3>
          <p className="set-desc">Recipes, prompts, and hosted-review defaults shared by the client.</p>
          <div className="set-row">
            <div className="set-row-body">
              <div className="set-row-title">Show source control AI actions</div>
              <div className="set-row-desc">Adds AI buttons that run the selected agent with the command template for that action.</div>
            </div>
            <div className="set-row-ctrl"><GitToggle name="showScAiActions" label="Show source control AI actions" /></div>
          </div>
        </div>

        <div className="set-section">
          <h3>Action recipes</h3>
          <p className="set-desc">Use variables only when you want the client to inject context. Leave the agent as default to follow your normal agent preference.</p>
          {[
            { h: 'Commit message', p: 'Generate the commit message from staged changes.', vars: '{basePrompt} {branch} {stagedFiles} {stagedPatch}' },
            { h: 'Pull request details', p: 'Generate the hosted review title and description.', vars: '{basePrompt} {branch} {baseBranch} {commitSummary} {changedFiles}' },
            { h: 'Branch name', p: 'Rename auto-created branches from the initial agent task.', vars: '{basePrompt} {firstPrompt} {assistantMessage}' },
          ].map((r) => (
            <div key={r.h} className="recipe-card">
              <div className="recipe-card-head">
                <div>
                  <h4>{r.h}</h4>
                  <p>{r.p}</p>
                </div>
                <select className="recipe-select">
                  <option>Use default agent</option>
                </select>
              </div>
              <div className="recipe-grid">
                <div>
                  <label>CLI arguments</label>
                  <input className="set-input" defaultValue="--model sonnet" />
                </div>
                <div>
                  <label>Command template</label>
                  <textarea defaultValue="{basePrompt}" />
                </div>
              </div>
              <div className="recipe-vars">{'{ }'} Variables: {r.vars}</div>
            </div>
          ))}
        </div>

        <div className="set-section">
          <h3>Custom command</h3>
          <p className="set-desc">
            Used by recipes that select Custom command. Use <code>{'{prompt}'}</code> to pass the command input as an argument; otherwise it is piped on stdin.
          </p>
          <input className="set-input" placeholder="e.g. ollama run llama3.1 {prompt}" value={customCommand} onChange={(e) => setGit('customCommand', e.target.value)} />
        </div>

        <div className="set-section">
          <h3>Hosted-review creation defaults</h3>
          <p className="set-desc">Used by repositories that inherit global hosted-review defaults.</p>
          <GitCheck name="draftPrByDefault" title="Draft by default" desc="Create hosted reviews as drafts unless changed in the composer." />
          <GitCheck name="usePrTemplate" title="Use review template when available" desc="Prefer repository pull request templates when no description is set." />
          <GitCheck name="generatePrOnOpen" title="Generate details when opening Create PR" desc="Run hosted-review detail generation once when the composer opens." />
          <GitCheck name="openPrAfterCreate" title="Open hosted review after creation" desc="Open the created hosted review in your browser after submit." />
        </div>

        <div className="set-section">
          <div className="budget-card recipe-card">
            <h4>GitHub API budget</h4>
            <p>Uses REST, Search, and GraphQL through the GitHub CLI. Budget scope: local machine.</p>
            <div className="recipe-vars">REST API: 4980 of 5000 left · resets in 11m</div>
            <div className="recipe-vars">Search API: 30 of 30 left · resets in 15s</div>
            <div className="recipe-vars">GraphQL API: 4983 of 5000 left · resets in 11m</div>
          </div>
        </div>
      </div>
    </div>
  )
}

function ColorRow({ title, desc, name }: { title: string; desc: string; name: 'railBg' | 'railFg' | 'sessionHighlight' }) {
  const value = useStore((s) => s.appearanceSettings[name])
  const setAppearance = useStore((s) => s.setAppearance)
  return (
    <div className="set-row">
      <div className="set-row-body">
        <div className="set-row-title">{title}</div>
        <div className="set-row-desc">{desc}</div>
      </div>
      <div className="set-row-ctrl color-ctrl color-ctrl-row">
        <input type="color" value={value} aria-label={title} onChange={(e) => setAppearance(name, e.target.value)} />
        <input className="set-input color-hex" spellCheck={false} value={value} onChange={(e) => setAppearance(name, e.target.value)} />
      </div>
    </div>
  )
}

function AppearancePane() {
  const ghosttyTheme = useStore((s) => s.appearanceSettings.ghosttyTheme)
  const railWidth = useStore((s) => s.appearanceSettings.railWidth)
  const setAppearance = useStore((s) => s.setAppearance)
  const active = GHOSTTY_THEMES[ghosttyTheme] || GHOSTTY_THEMES['catppuccin-frappe']

  return (
    <div className="settings-pane">
      <p className="settings-pane-intro">Terminal colors come from Ghostty. Customize the side rail here.</p>
      <div className="settings-scroll">
        <div className="set-section">
          <h3>Terminal</h3>
          <p className="set-desc">Imported from your Ghostty theme — rendered by Ghostty’s engine (ghostty-web).</p>
          <div className="ghostty-import">
            <div className="ghostty-import-swatch" style={{ background: `linear-gradient(135deg, ${active.swatch.join(',')})` }} />
            <div className="ghostty-import-body">
              <div className="ghostty-import-label">Imported theme</div>
              <div className="ghostty-import-theme">{ghosttyTheme}</div>
              <div className="ghostty-import-meta">~/.config/ghostty/config</div>
              <div className="ghostty-import-meta">{active.config}</div>
            </div>
          </div>
          <div className="ghostty-theme-grid">
            {Object.entries(GHOSTTY_THEMES).map(([key, def]) => (
              <button
                key={key}
                type="button"
                className={'ghostty-theme-chip' + (key === ghosttyTheme ? ' on' : '')}
                onClick={() => setAppearance('ghosttyTheme', key)}
              >
                <span className="sw" style={{ background: `linear-gradient(135deg, ${def.swatch.join(',')})` }} />
                {def.label}
              </button>
            ))}
          </div>
        </div>

        <div className="set-section">
          <h3>Side rail</h3>
          <p className="set-desc">App chrome only — does not affect the terminal pane.</p>
          <ColorRow title="Background" desc="Main rail color." name="railBg" />
          <ColorRow title="Foreground" desc="Primary text color in the rail." name="railFg" />
          <div className="set-row">
            <div className="set-row-body">
              <div className="set-row-title">Rail width</div>
              <div className="set-row-desc">Horizontal space for the project tree.</div>
            </div>
            <div className="set-row-ctrl">
              <div className="set-seg">
                {(['compact', 'default', 'wide'] as const).map((w) => (
                  <button key={w} type="button" className={railWidth === w ? 'on' : ''} onClick={() => setAppearance('railWidth', w)}>
                    {w[0].toUpperCase() + w.slice(1)}
                  </button>
                ))}
              </div>
            </div>
          </div>
          <ColorRow title="Active session highlight" desc="Border and fill for the selected session row." name="sessionHighlight" />
        </div>
      </div>
    </div>
  )
}

export function SettingsPanel() {
  const open = useUi((s) => s.settingsOpen)
  const tab = useUi((s) => s.settingsTab)
  const setTab = useUi((s) => s.setSettingsTab)
  const close = useUi((s) => s.closeSettings)
  if (!open) return null

  return (
    <>
      <div className="scrim" onClick={close} />
      <div className="settings-panel">
        <div className="settings-head">
          <h2>Settings</h2>
          <button type="button" className="icon-btn" title="Close" onClick={close}>
            <CloseIcon />
          </button>
        </div>
        <div className="settings-tabs">
          {([['agents', 'Agents'], ['git', 'Git + Source Control'], ['appearance', 'Appearance']] as const).map(([id, label]) => (
            <button key={id} type="button" className={'settings-tab' + (tab === id ? ' on' : '')} onClick={() => setTab(id)}>
              {label}
            </button>
          ))}
        </div>
        <div className="settings-body">
          {tab === 'agents' && <AgentsPane />}
          {tab === 'git' && <GitPane />}
          {tab === 'appearance' && <AppearancePane />}
        </div>
      </div>
    </>
  )
}
