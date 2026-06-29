// The Sacred Terminal — PTY bridge.
//
// Real pseudo-terminals (node-pty) streamed to the browser over WebSocket.
// The browser renders them with Ghostty's engine (ghostty-web / libghostty WASM).
//
// Sessions are *hosted*: a pty keeps running even after every browser socket
// detaches, and its recent output is replayed on reattach. This is the real
// counterpart to the spec's "always running" model — close the tab, the agent
// keeps working; reopen, the scrollback is still there.

import http from 'node:http'
import os from 'node:os'
import fs from 'node:fs'
import path from 'node:path'
import { WebSocketServer } from 'ws'

let pty
try {
  pty = await import('node-pty')
} catch (err) {
  console.error('[pty-server] failed to load node-pty:', err?.message || err)
  process.exit(1)
}

const PORT = Number(process.env.PTY_PORT || 5174)
const SCROLLBACK_LIMIT = 256 * 1024 // bytes of replay kept per session

// Agent roster — mirrors the UI roster and the spec's YOLO table (§7).
const AGENTS = {
  claude: { cmd: 'claude', yolo: '--dangerously-skip-permissions', label: 'Claude Code' },
  codex: { cmd: 'codex', yolo: '--dangerously-bypass-approvals-and-sandbox', label: 'Codex' },
  cursor: { cmd: 'cursor-agent', yolo: '--yolo', label: 'Cursor Agent' },
  gemini: { cmd: 'gemini', yolo: '--yolo', label: 'Gemini' },
  copilot: { cmd: 'copilot', yolo: null, label: 'Copilot' },
  opencode: { cmd: 'opencode', yolo: null, label: 'OpenCode' },
  shell: { cmd: null, yolo: null, label: 'Shell' },
}

const DEFAULT_SHELL = process.env.SHELL || (os.platform() === 'win32' ? 'powershell.exe' : 'bash')

// Resolve an executable against PATH (so we can fall back to a shell when an
// agent CLI isn't installed — the terminal stays real either way).
function which(bin) {
  if (!bin) return null
  if (bin.includes('/')) return fs.existsSync(bin) ? bin : null
  const dirs = (process.env.PATH || '').split(path.delimiter)
  for (const dir of dirs) {
    if (!dir) continue
    const full = path.join(dir, bin)
    try {
      fs.accessSync(full, fs.constants.X_OK)
      return full
    } catch {
      /* keep looking */
    }
  }
  return null
}

function resolveLaunch(agentKey, yolo) {
  const agent = AGENTS[agentKey] || AGENTS.shell
  if (agent.cmd) {
    const resolved = which(agent.cmd)
    if (resolved) {
      const args = yolo && agent.yolo ? [agent.yolo] : []
      return { file: resolved, args, note: null, agent }
    }
    // Agent CLI not on PATH — open a real shell, but say so.
    return {
      file: which(DEFAULT_SHELL) || DEFAULT_SHELL,
      args: [],
      note: `${agent.label} (\`${agent.cmd}\`) is not on PATH — opened a real shell instead. Install the CLI to launch it here.`,
      agent,
    }
  }
  return { file: which(DEFAULT_SHELL) || DEFAULT_SHELL, args: [], note: null, agent }
}

/** @type {Map<string, {pty: any, buffer: string, sockets: Set<any>, meta: object}>} */
const sessions = new Map()

function appendBuffer(sess, chunk) {
  sess.buffer += chunk
  if (sess.buffer.length > SCROLLBACK_LIMIT) {
    sess.buffer = sess.buffer.slice(sess.buffer.length - SCROLLBACK_LIMIT)
  }
}

function spawnSession(sid, opts) {
  const cwdRaw = opts.cwd || process.cwd()
  const cwd = fs.existsSync(cwdRaw) ? cwdRaw : process.cwd()
  const launch = resolveLaunch(opts.agent, opts.yolo)
  const child = pty.spawn(launch.file, launch.args, {
    name: 'xterm-256color',
    cols: opts.cols || 80,
    rows: opts.rows || 24,
    cwd,
    env: { ...process.env, TERM: 'xterm-256color', SACRED_TERMINAL: '1' },
  })

  const sess = {
    pty: child,
    buffer: '',
    sockets: new Set(),
    meta: { sid, agent: opts.agent, cwd, file: launch.file, pid: child.pid },
  }
  sessions.set(sid, sess)

  if (launch.note) {
    // Seed the banner into scrollback; the connecting socket gets it via replay,
    // and any already-attached sockets get it on the next data flush.
    appendBuffer(sess, `\x1b[38;5;221m${launch.note}\x1b[0m\r\n`)
  }

  child.onData((data) => {
    appendBuffer(sess, data)
    broadcast(sess, data)
  })
  child.onExit(({ exitCode }) => {
    const msg = `\r\n\x1b[38;5;245m[process exited — code ${exitCode}]\x1b[0m\r\n`
    appendBuffer(sess, msg)
    broadcast(sess, msg)
    sessions.delete(sid)
  })

  console.log(`[pty-server] spawn sid=${sid} agent=${opts.agent} -> ${launch.file} ${launch.args.join(' ')} (pid ${child.pid}, cwd ${cwd})`)
  return sess
}

function broadcast(sess, data) {
  for (const ws of sess.sockets) {
    if (ws.readyState === ws.OPEN) {
      try {
        ws.send(data)
      } catch {
        /* drop */
      }
    }
  }
}

const server = http.createServer((req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(200, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ ok: true, sessions: sessions.size }))
    return
  }
  res.writeHead(404)
  res.end()
})

const wss = new WebSocketServer({ server, path: '/pty' })

wss.on('connection', (ws, req) => {
  const url = new URL(req.url, 'http://localhost')
  const sid = url.searchParams.get('sid') || `s${Date.now()}`
  const agent = url.searchParams.get('agent') || 'shell'
  const cwd = url.searchParams.get('cwd') || process.cwd()
  const yolo = url.searchParams.get('yolo') === '1'
  const cols = Number(url.searchParams.get('cols')) || 80
  const rows = Number(url.searchParams.get('rows')) || 24

  let sess = sessions.get(sid)
  const isReattach = !!sess
  if (!sess) sess = spawnSession(sid, { agent, cwd, yolo, cols, rows })
  sess.sockets.add(ws)

  // Replay scrollback so reconnecting clients see prior output.
  if (sess.buffer) {
    try {
      ws.send(sess.buffer)
    } catch {
      /* ignore */
    }
  }
  // Tell the client what it attached to.
  try {
    ws.send(`\x00META${JSON.stringify({ ...sess.meta, reattached: isReattach })}`)
  } catch {
    /* ignore */
  }

  ws.on('message', (raw) => {
    let msg
    try {
      msg = JSON.parse(raw.toString())
    } catch {
      return
    }
    if (msg.t === 'i') {
      sess.pty.write(msg.d)
    } else if (msg.t === 'r') {
      try {
        sess.pty.resize(Math.max(1, msg.c | 0), Math.max(1, msg.r | 0))
      } catch {
        /* ignore */
      }
    } else if (msg.t === 'kill') {
      try {
        sess.pty.kill()
      } catch {
        /* ignore */
      }
    }
  })

  ws.on('close', () => {
    sess.sockets.delete(ws)
    // Session is intentionally NOT killed — it keeps running (hosted process).
  })
})

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[pty-server] listening on ws://127.0.0.1:${PORT}/pty`)
})
