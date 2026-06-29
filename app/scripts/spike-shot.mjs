import { chromium } from 'playwright'

const url = process.env.URL || 'http://127.0.0.1:5173/'
const out = process.env.OUT || 'spike.png'

const browser = await chromium.launch()
const ctx = await browser.newContext({ viewport: { width: 1280, height: 820 }, deviceScaleFactor: 2 })
const page = await ctx.newPage()
page.on('console', (m) => console.log('[page]', m.type(), m.text()))
page.on('pageerror', (e) => console.log('[pageerror]', e.message))

await page.goto(url, { waitUntil: 'networkidle' })
await page.waitForTimeout(2800) // wasm init + ws connect + shell prompt

// Focus the terminal and type a real command.
await page.locator('.term-host').click({ position: { x: 200, y: 200 } })
await page.waitForTimeout(200)
await page.keyboard.type('echo "hello from a real ghostty terminal" && uname -sm && ls')
await page.keyboard.press('Enter')
await page.waitForTimeout(1500)

await page.screenshot({ path: out })
console.log('wrote', out)
await browser.close()
