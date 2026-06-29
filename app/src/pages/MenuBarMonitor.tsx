import { useMemo, useState } from 'react'
import { useStore } from '../store'
import { AgentIcon } from '../lib/icons'
import type { Project, Session } from '../types'

const CSS = `
.mbm { --bg:#08080a; --text:#f2f2f4; --text-dim:#9a9aa3; --text-faint:#5b5b63; --orange:#fab387; --green:#a6d189; --blue:#8caaee; --pink:#f2a4db; --ring:#e5c890; --notify:#2f6fed;
  --ui:'Inter',-apple-system,BlinkMacSystemFont,system-ui,sans-serif; --mono:'JetBrains Mono','SF Mono',ui-monospace,monospace;
  min-height:100vh; background:radial-gradient(circle at 1px 1px, rgba(255,255,255,.045) 1px, transparent 1.6px) 0 0/23px 23px, var(--bg); color:var(--text); font-family:var(--ui); overflow-x:hidden; }
.mbm .wrap { max-width:1180px; margin:0 auto; padding:72px 56px 0; }
.mbm .eyebrow { font-family:var(--mono); font-size:14px; color:var(--text-faint); margin-bottom:22px; }
.mbm h1 { font-weight:800; font-size:clamp(38px,6vw,68px); line-height:1.03; letter-spacing:-.025em; max-width:15ch; }
.mbm .lede { margin-top:26px; max-width:640px; font-size:clamp(16px,1.7vw,20px); line-height:1.55; color:var(--text-dim); }
.mbm .lede b { color:var(--text); font-weight:600; }
.mbm .stage { margin-top:54px; }
.mbm .desktop { position:relative; height:560px; border-radius:16px 16px 0 0; overflow:hidden; background:radial-gradient(120% 90% at 75% -10%, #5a4a86 0%, #3a3160 38%, #262238 70%, #1d1b29 100%); box-shadow:0 -1px 0 rgba(255,255,255,.06) inset, 0 40px 120px rgba(0,0,0,.5); border:1px solid rgba(255,255,255,.06); border-bottom:none; }
.mbm .menubar { height:30px; display:flex; align-items:center; gap:18px; padding:0 14px; background:rgba(16,15,22,.5); backdrop-filter:blur(20px); border-bottom:1px solid rgba(255,255,255,.06); font-size:13px; color:#eceaf2; position:relative; z-index:5; }
.mbm .menubar .app { font-weight:700; }
.mbm .menubar .mi { color:#d7d5df; opacity:.92; }
.mbm .menubar .spacer { flex:1; }
.mbm .menubar .tray { display:flex; align-items:center; gap:15px; }
.mbm .clock { font-variant-numeric:tabular-nums; font-size:12.5px; }
.mbm .pulse { position:relative; width:22px; height:22px; display:grid; place-items:center; cursor:pointer; border-radius:6px; }
.mbm .pulse:hover, .mbm .pulse.active { background:rgba(255,255,255,.12); }
.mbm .pulse .spin { width:15px; height:15px; color:#fff; animation:mbmspin 2.6s linear infinite; }
@keyframes mbmspin { to { transform:rotate(360deg); } }
.mbm .pulse .ring { position:absolute; inset:-2px; border-radius:8px; border:1.5px solid var(--ring); opacity:0; animation:mbmring 2.4s ease-out infinite; }
@keyframes mbmring { 0%{transform:scale(.7);opacity:.9;} 70%{transform:scale(1.5);opacity:0;} 100%{opacity:0;} }
.mbm .pulse .badge { position:absolute; top:-1px; right:-1px; width:7px; height:7px; border-radius:50%; background:var(--notify); box-shadow:0 0 0 1.5px rgba(16,15,22,.9); }
.mbm .menu { position:absolute; z-index:6; top:38px; right:12px; width:440px; background:rgba(26,26,32,.86); backdrop-filter:blur(34px) saturate(1.4); border:1px solid rgba(255,255,255,.09); border-radius:14px; box-shadow:0 30px 80px rgba(0,0,0,.55), 0 0 0 .5px rgba(255,255,255,.04) inset; padding:7px; transform-origin:top right; }
.mbm .menu .caret { position:absolute; top:-6px; right:60px; width:12px; height:12px; background:rgba(26,26,32,.86); border-left:1px solid rgba(255,255,255,.09); border-top:1px solid rgba(255,255,255,.09); transform:rotate(45deg); }
.mbm .row { display:flex; align-items:center; gap:13px; padding:11px 13px; border-radius:10px; cursor:pointer; position:relative; }
.mbm .row:hover, .mbm .row.active { background:rgba(255,255,255,.06); }
.mbm .row .lead { width:18px; flex:0 0 18px; display:grid; place-items:center; }
.mbm .row .body { flex:1; min-width:0; }
.mbm .row .title { font-size:14px; font-weight:500; color:#f1f0f5; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.mbm .row .sub { font-size:12px; color:var(--text-faint); margin-top:2px; }
.mbm .row .ident { width:22px; flex:0 0 22px; display:grid; place-items:center; }
.mbm .mini { width:13px; height:13px; border-radius:50%; border:2px solid rgba(255,255,255,.16); border-top-color:currentColor; animation:mbmspin 1s linear infinite; }
.mbm .mini.c-orange { color:var(--orange); } .mbm .mini.c-green { color:var(--green); } .mbm .mini.c-blue { color:var(--blue); }
.mbm .appicon { width:18px; height:18px; border-radius:5px; background:linear-gradient(160deg,#3a3a44,#222229); border:1px solid rgba(255,255,255,.12); display:grid; place-items:center; }
.mbm .dot-notify { width:8px; height:8px; border-radius:50%; background:var(--notify); }
.mbm .sep { height:1px; background:rgba(255,255,255,.07); margin:6px 10px; }
.mbm .caption { text-align:center; font-family:var(--mono); font-size:12px; color:var(--text-faint); padding:18px 0 40px; }
.mbm .caption b { color:var(--text-dim); font-weight:500; }
.mbm .toast { position:fixed; left:50%; bottom:28px; transform:translateX(-50%) translateY(20px); background:rgba(20,20,26,.95); border:1px solid rgba(255,255,255,.1); color:#ececf2; padding:11px 18px; border-radius:10px; font-size:13.5px; box-shadow:0 20px 50px rgba(0,0,0,.5); opacity:0; pointer-events:none; transition:opacity .2s, transform .2s; z-index:30; font-family:var(--mono); }
.mbm .toast.show { opacity:1; transform:translateX(-50%) translateY(0); }
.mbm a.back { position:fixed; top:18px; left:22px; color:var(--text-dim); font-family:var(--mono); font-size:13px; text-decoration:none; z-index:40; }
.mbm a.back:hover { color:var(--text); }
`

type Row = { project: Project; session: Session }

export function MenuBarMonitor() {
  const projects = useStore((s) => s.projects)
  const [toast, setToast] = useState('')

  const rows: Row[] = useMemo(
    () => projects.flatMap((p) => p.sessions.map((s) => ({ project: p, session: s }))),
    [projects],
  )
  const anyWorking = rows.some((r) => r.session.status === 'working')
  const anyWaiting = rows.some((r) => r.session.status === 'waiting')
  const order: Record<string, number> = { working: 0, done: 1, idle: 2, waiting: 3 }
  const sorted = [...rows].sort((a, b) => order[a.session.status] - order[b.session.status])
  const needs = sorted.filter((r) => r.session.status === 'waiting')
  const rest = sorted.filter((r) => r.session.status !== 'waiting')

  const open = (r: Row) => {
    setToast(`Opening "${r.session.task}" — snapping the window back…`)
    window.clearTimeout((open as any)._t)
    ;(open as any)._t = window.setTimeout(() => setToast(''), 2800)
  }

  const lead = (s: Session) => {
    if (s.status === 'working') return <span className="mini c-green" />
    if (s.status === 'waiting') return <span className="mini c-orange" />
    if (s.status === 'done') return <span className="mini c-blue" />
    return (
      <span className="appicon">
        <AgentIcon agent={s.agent} size={12} />
      </span>
    )
  }

  const renderRow = (r: Row, i: number) => (
    <div key={r.session.id} className={'row' + (i === 0 && rest.length ? ' active' : '')} onClick={() => open(r)}>
      <span className="lead">{lead(r.session)}</span>
      <span className="body">
        <div className="title">{r.session.task}</div>
        <div className="sub">
          {r.project.name}
          {r.session.status === 'waiting' ? ' · needs your input' : ''}
        </div>
      </span>
      <span className="ident">
        {r.session.status === 'waiting' ? <span className="dot-notify" /> : <AgentIcon agent={r.session.agent} size={16} />}
      </span>
    </div>
  )

  return (
    <div className="mbm">
      <style>{CSS}</style>
      <a className="back" href="#">
        ← back to the workspace
      </a>
      <div className="wrap">
        <div className="eyebrow">Always running</div>
        <h1>Close the window. Your agents keep working.</h1>
        <p className="lede">
          Every session runs in its own <b>hosted process</b>, so it survives quitting the window. A menu-bar item keeps a live pulse
          on all of them — it <b>spins</b> whenever an agent is working and <b>rings</b> when one needs you. Click it for the full
          roster, pick one, and The Sacred Terminal <b>snaps the window back open</b> right to that conversation.
        </p>

        <div className="stage">
          <div className="desktop">
            <div className="menubar">
              <span className="app">Sacred</span>
              <span className="mi">File</span>
              <span className="mi">Edit</span>
              <span className="mi">View</span>
              <span className="mi">Window</span>
              <span className="mi">Help</span>
              <span className="spacer" />
              <span className="tray">
                <span className={'pulse active'} title={`${rows.filter((r) => r.session.status === 'working').length} working · ${needs.length} needs you`}>
                  <svg className="spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" style={{ animationPlayState: anyWorking ? 'running' : 'paused' }}>
                    <path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M18.4 5.6l-2.1 2.1M7.7 16.3l-2.1 2.1" opacity=".9" />
                  </svg>
                  {anyWaiting && <span className="ring" />}
                  {anyWaiting && <span className="badge" />}
                </span>
                <span className="clock">Mon 22 Jun&nbsp;&nbsp;14:04</span>
              </span>
            </div>

            <div className="menu">
              <div className="caret" />
              {rest.map((r, i) => renderRow(r, i))}
              {needs.length > 0 && <div className="sep" />}
              {needs.map((r, i) => renderRow(r, rest.length + i))}
            </div>
          </div>
          <div className="caption">
            <b>The Sacred Terminal</b> — menu-bar monitor · window closed, agents still running
          </div>
        </div>
      </div>
      <div className={'toast' + (toast ? ' show' : '')}>{toast}</div>
    </div>
  )
}
