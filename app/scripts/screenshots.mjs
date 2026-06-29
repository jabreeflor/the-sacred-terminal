import { chromium } from 'playwright'
import { mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const __dir = dirname(fileURLToPath(import.meta.url))
const OUT = join(__dir, '..', '..', 'docs', 'app-screenshots')
mkdirSync(OUT, { recursive: true })

const BASE = process.env.URL || 'http://127.0.0.1:5173/'
const VW = 1380
const VH = 880

const browser = await chromium.launch()
// Fresh context => empty localStorage => deterministic seed on first load.
// We do NOT clear on every navigation, so reloads can preserve session state.
const ctx = await browser.newContext({ viewport: { width: VW, height: VH }, deviceScaleFactor: 2 })
const page = await ctx.newPage()
page.on('pageerror', (e) => console.log('[pageerror]', e.message))

const wait = (ms) => page.waitForTimeout(ms)
async function shot(name) {
  await page.screenshot({ path: join(OUT, name) })
  console.log('  ✓', name)
}
async function step(name, fn) {
  try {
    await fn()
    await shot(name)
  } catch (e) {
    console.log('  ✗', name, '-', e.message)
  }
}

await page.goto(BASE, { waitUntil: 'domcontentloaded' })
await wait(3500) // wasm init + ws + real agent boot

// 1. Default workspace — real agent in a Ghostty-rendered pane
await shot('01-workspace.png')

// 2. Agent pre-open picker (hover a project -> open the "more agents" pill)
await step('02-agent-picker.png', async () => {
  const row = page.locator('.project-row').first()
  await row.hover()
  await wait(200)
  await row.locator('.agent-bar button').last().click({ force: true })
  await wait(300)
})
await page.keyboard.press('Escape')
await wait(150)

// 3-5. Settings tabs
await step('03-settings-agents.png', async () => {
  await page.locator('.rail-top .icon-btn').first().click()
  await wait(300)
})
await step('04-settings-appearance.png', async () => {
  await page.locator('.settings-tab', { hasText: 'Appearance' }).click()
  await wait(250)
})
await step('05-settings-git.png', async () => {
  await page.locator('.settings-tab', { hasText: 'Git' }).click()
  await wait(250)
})
await page.keyboard.press('Escape')
await wait(150)

// 6. Integrated browser — select the session that ships with a browser preview
await step('06-integrated-browser.png', async () => {
  await page.locator('.session', { hasText: 'Tighten the rail' }).click()
  await wait(300)
  // Reload so ONLY the now-active session's pane mounts (no canvas overlap from
  // the previously-active session) — the browser stays open via persisted state.
  await page.reload({ waitUntil: 'domcontentloaded' })
  await wait(2600)
})

// 7. Terminal splits — split the active session into two real panes
await step('07-splits.png', async () => {
  await page.locator('.session', { hasText: 'Implement the spec' }).click()
  await wait(800)
  await page.locator('.term-tab-actions button[title^="Split right"]').click()
  await wait(1800)
})

// 8. Rail collapsed — full-width terminal
await step('08-rail-collapsed.png', async () => {
  await page.locator('.titlebar .icon-btn').first().click()
  await wait(500)
})
// restore rail
await page.locator('.titlebar .icon-btn').first().click()
await wait(300)

// 9. Menu-bar "always running" monitor (live roster from the same store)
await step('09-menu-bar.png', async () => {
  await page.goto(BASE + '#menu-bar', { waitUntil: 'domcontentloaded' })
  await wait(1000)
})

await browser.close()
console.log('done ->', OUT)
