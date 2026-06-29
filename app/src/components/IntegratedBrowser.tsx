import { useEffect, useState } from 'react'
import type { Session } from '../types'
import { useStore } from '../store'
import { useUi } from '../ui'

function resolveSrc(url: string) {
  if (/^https?:\/\//i.test(url)) return url
  if (url.startsWith('/')) return url
  return '/preview.html'
}

export function IntegratedBrowser({ session }: { session: Session }) {
  const setBrowserUrl = useStore((s) => s.setBrowserUrl)
  const toggleBrowser = useStore((s) => s.toggleBrowser)
  const showToast = useUi((s) => s.showToast)

  const [draft, setDraft] = useState(session.browserUrl)
  const [committed, setCommitted] = useState(session.browserUrl)
  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    setDraft(session.browserUrl)
    setCommitted(session.browserUrl)
  }, [session.id, session.browserUrl])

  useEffect(() => {
    function onMessage(e: MessageEvent) {
      if (!e.data || e.data.type !== 'browser-send') return
      showToast(`Sent ref ${e.data.ref} (${e.data.tag}) to the agent`)
    }
    window.addEventListener('message', onMessage)
    return () => window.removeEventListener('message', onMessage)
  }, [showToast])

  const commit = () => {
    const v = draft.trim() || committed
    setCommitted(v)
    setBrowserUrl(session.id, v)
  }

  return (
    <div className="browser-pane">
      <div className="browser-toolbar">
        <button title="Back" aria-label="Back">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M15 18l-6-6 6-6" /></svg>
        </button>
        <button title="Forward" aria-label="Forward">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M9 18l6-6-6-6" /></svg>
        </button>
        <button title="Reload" aria-label="Reload" onClick={() => setReloadKey((k) => k + 1)}>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M21 12a9 9 0 1 1-2.64-6.36" /><path d="M21 3v6h-6" /></svg>
        </button>
        <div className="browser-url">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="9" /><path d="M3 12h18" /><path d="M12 3a14 14 0 0 1 0 18" /></svg>
          <input
            type="text"
            spellCheck={false}
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') commit()
            }}
          />
        </div>
        <button title="Close browser" aria-label="Close browser" onClick={() => toggleBrowser(session.id, false)}>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" /></svg>
        </button>
      </div>
      <div className="browser-frame-wrap">
        <iframe key={reloadKey} className="browser-frame" src={resolveSrc(committed)} title="Session preview" />
      </div>
    </div>
  )
}
