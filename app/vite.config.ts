import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// ghostty-web ships a .wasm asset; make sure Vite treats it as an asset and
// does not try to pre-bundle the wasm loader in a way that breaks init().
export default defineConfig({
  plugins: [react()],
  server: {
    host: '127.0.0.1',
    port: 5173,
    proxy: {
      // PTY websocket bridge -> node-pty server
      '/pty': {
        target: 'ws://127.0.0.1:5174',
        ws: true,
      },
    },
  },
  optimizeDeps: {
    exclude: ['ghostty-web'],
  },
  assetsInclude: ['**/*.wasm'],
})
