import { createRequire } from 'module';
const require = createRequire((process.env.PLAYWRIGHT_DIR || '/opt/node22/lib/node_modules/playwright') + '/');
const { chromium } = require(process.env.PLAYWRIGHT_DIR || '/opt/node22/lib/node_modules/playwright');
const url = process.argv[2] || 'http://127.0.0.1:8765/index.html';
const wait = +(process.argv[3] || 15000);
const out = process.argv[4] || 'shot.png';
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--no-proxy-server'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
page.on('console', m => { const t = m.text(); if (!/^OUT /.test(t) || process.env.V) console.log('[c]', t.slice(0, 400)); });
page.on('pageerror', e => console.log('[pageerror]', e.message));
await page.goto(url);
await page.waitForTimeout(wait);
if (process.env.ACT) { const f = new Function('page', 'return (async () => {' + process.env.ACT + '})()'); await f(page); }
console.log('frames', await page.evaluate(() => window.__frames));
await page.screenshot({ path: out });
await browser.close();
