import type { AppearanceSettings } from '../types'

const RAIL_WIDTHS: Record<AppearanceSettings['railWidth'], string> = {
  compact: '220px',
  default: '252px',
  wide: '288px',
}

function normalizeHex(hex: string): string | null {
  if (!hex) return null
  let h = String(hex).trim().toLowerCase()
  if (!h.startsWith('#')) h = '#' + h
  if (/^#[0-9a-f]{3}$/.test(h)) h = '#' + h[1] + h[1] + h[2] + h[2] + h[3] + h[3]
  return /^#[0-9a-f]{6}$/.test(h) ? h : null
}

function hexToRgb(hex: string) {
  const h = normalizeHex(hex)
  if (!h) return null
  const n = parseInt(h.slice(1), 16)
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 }
}

function shadeHex(hex: string, amount: number) {
  const rgb = hexToRgb(hex)
  if (!rgb) return hex
  const clamp = (v: number) => Math.min(255, Math.max(0, v + amount))
  return '#' + [clamp(rgb.r), clamp(rgb.g), clamp(rgb.b)].map((c) => c.toString(16).padStart(2, '0')).join('')
}

function rgba(hex: string, alpha: number) {
  const rgb = hexToRgb(hex)
  if (!rgb) return `rgba(250,179,135,${alpha})`
  return `rgba(${rgb.r},${rgb.g},${rgb.b},${alpha})`
}

/** Apply the rail/chrome appearance to CSS custom properties on :root. */
export function applyAppearance(a: AppearanceSettings) {
  const root = document.documentElement
  const bg = normalizeHex(a.railBg) || '#0a0a0c'
  const fg = normalizeHex(a.railFg) || '#e6e6ea'
  root.style.setProperty('--rail-bg', bg)
  root.style.setProperty('--chrome-bg', shadeHex(bg, 4))
  root.style.setProperty('--titlebar-bg', shadeHex(bg, 14))
  root.style.setProperty('--panel-bg', shadeHex(bg, 2))
  root.style.setProperty('--border', shadeHex(bg, 22))
  root.style.setProperty('--border-soft', shadeHex(bg, 14))
  root.style.setProperty('--hover', shadeHex(bg, 12))
  root.style.setProperty('--text', fg)
  root.style.setProperty('--text-dim', rgba(fg, 0.55))
  root.style.setProperty('--text-faint', rgba(fg, 0.35))
  root.style.setProperty('--rail-w', RAIL_WIDTHS[a.railWidth] || RAIL_WIDTHS.default)
  const hi = normalizeHex(a.sessionHighlight) || '#fab387'
  root.style.setProperty('--session-active-bg', rgba(hi, 0.06))
  root.style.setProperty('--session-active-border', rgba(hi, 0.45))
  root.style.setProperty('--session-active-glow', rgba(hi, 0.12))
}
