import { useEffect, useState } from 'react'
import { createRoot } from 'react-dom/client'
import './theme/app.css'
import { App } from './App'
import { MenuBarMonitor } from './pages/MenuBarMonitor'

function Root() {
  const [hash, setHash] = useState(location.hash)
  useEffect(() => {
    const onHash = () => setHash(location.hash)
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])
  return hash === '#menu-bar' ? <MenuBarMonitor /> : <App />
}

createRoot(document.getElementById('root')!).render(<Root />)
