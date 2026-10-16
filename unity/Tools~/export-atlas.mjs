// Exports every sprite of the browser version (game/sprites.js) into one PNG atlas + a JSON index for Unity.
// Run from the repository root:  node unity/Tools~/export-atlas.mjs
// Needs Node and Playwright with Chromium. Writes unity/Assets/Ogorod/Resources/Ogorod/atlas.bytes and atlasindex.json.
import fs from 'fs';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';
import { createRequire } from 'module';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const out = path.join(root, 'unity/Assets/Ogorod/Resources/Ogorod');
const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); }
catch { ({ chromium } = await import(pathToFileURL(path.join(process.env.PLAYWRIGHT_DIR || '', 'index.mjs')).href)); }

const browser = await chromium.launch();
const page = await browser.newPage();
await page.setContent('<html><body></body></html>');
await page.addScriptTag({ content: fs.readFileSync(path.join(root, 'game/sprites.js'), 'utf8') });

const result = await page.evaluate(() => {
  const S = window.OgorodSprites, T = 16, items = [];
  const canvas = (w, h, fn) => { const c = document.createElement('canvas'); c.width = w; c.height = h; const g = c.getContext('2d'); g.imageSmoothingEnabled = false; fn(g); return c; };
  const add = (n, c, ax = 0, ay = 0, fy = c.height) => items.push({ n, c, ax, ay, fy });
  const obj = (n, o) => add(n, o.img, o.ax, o.ay, o.fy);
  const tile = (n, fn) => add(n, canvas(16, 16, fn));

  /* the looks of the year: 12 spring days, summer, 12 autumn days, winter with and without snow */
  const looks = [];
  for (let d = 1; d <= 12; d++) looks.push(['spring' + String(d).padStart(2, '0'), S.lookFor(d, false)]);
  looks.push(['summer', S.lookFor(13, false)]);
  for (let d = 1; d <= 12; d++) looks.push(['autumn' + String(d).padStart(2, '0'), S.lookFor(24 + d, false)]);
  looks.push(['winter', S.lookFor(37, false)], ['wintersnow', S.lookFor(37, true)]);
  const SUMMER = S.lookFor(13, false), SNOW = S.lookFor(37, true);

  for (const f of ['down', 'left', 'right', 'up']) for (const fr of [0, 1]) obj(`player_${f}_${fr}`, S.sprite('player', f, fr));
  for (const k of Object.keys(S.CROPS)) if (k !== 'apple') for (let st = 0; st < 4; st++) obj(`crop_${k}_${st}`, S.sprite('crop', k, st, SUMMER));
  obj('dead', S.sprite('dead', 0, 0, SUMMER)); obj('dead_snow', S.sprite('dead', 0, 0, SNOW));
  for (const [ln, L] of looks) {
    S.clearCache();
    obj(`tree0_${ln}`, S.sprite('tree', 0, 0, L)); obj(`tree1_${ln}`, S.sprite('tree', 1, 0, L));
    obj(`bush_${ln}`, S.sprite('bush', 0, 0, L)); obj(`bigtree_${ln}`, S.sprite('bigtree', 0, 0, L));
    for (let st = 0; st < 4; st++) obj(`crop_apple_${st}_${ln}`, S.sprite('crop', 'apple', st, L));
    for (let i = 0; i < 4; i++) tile(`grass_${ln}_${i}`, g => { g.translate(-i * T, -50 * T); S.drawGrass(g, i, 50, L.grass); if (L.fallen && i < 3) S.drawFallen(g, i, 50, L.fallen); });
  }
  S.clearCache();
  for (const mode of ['bloom', 'some', 'wither']) for (let i = 0; i < 8; i++) obj(`flower_${mode}_${i}`, S.sprite('flower', i, 77, { ...SUMMER, flowers: mode, key: 'f' + mode }));
  for (const [sfx, L] of [['', SUMMER], ['_snow', SNOW]]) {
    obj('house0' + sfx, S.sprite('house', false, 0, L)); obj('house1' + sfx, S.sprite('house', true, 0, L));
    for (const k of ['well', 'bin', 'mailbox', 'sign', 'stake', 'rock', 'twigs', 'stump']) obj(k + sfx, S.sprite(k, 0, 0, L));
  }
  for (let i = 0; i < 4; i++) {
    tile(`snow_${i}`, g => { g.translate(-i * T, -60 * T); S.drawSnow(g, i, 60); });
    tile(`path_${i}`, g => { g.translate(-i * T, -60 * T); S.drawPath(g, i, 60); });
    tile(`site_${i}`, g => { g.translate(-i * T, -60 * T); S.drawSite(g, i, 60); });
    tile(`ice_${i}`, g => { g.translate(-i * T, -60 * T); S.drawWater(g, i, 60, 0, false, true); });
    tile(`trodden_${i}`, g => { g.translate(-i * T, -60 * T); S.drawTrodden(g, i, 60); });
    for (let f = 0; f < 4; f++) tile(`water_${i}_${f}`, g => { g.translate(-i * T, -60 * T); S.drawWater(g, i, 60, f * 0.6, false, false); });
  }
  tile('soil', g => S.drawSoil(g, 0, 0, false)); tile('soilwet', g => S.drawSoil(g, 0, 0, true));
  for (const k of ['hoe', 'can', 'axe', 'pick', 'scythe', 'wood', 'stone']) add('icon_' + k, S.iconCanvas(k));
  for (const k of Object.keys(S.CROPS)) { add('seed_' + k, S.iconCanvas('seed', k)); add('prod_' + k, S.iconCanvas('prod', k)); }

  /* shelf packing with 1 px of empty space around every sprite */
  items.sort((a, b) => b.c.height - a.c.height);
  const AW = 1024; let x = 1, y = 1, shelf = 0;
  for (const it of items) {
    if (x + it.c.width + 1 > AW) { x = 1; y += shelf + 1; shelf = 0; }
    it.x = x; it.y = y; x += it.c.width + 1; shelf = Math.max(shelf, it.c.height);
  }
  const AH = 1 << Math.ceil(Math.log2(y + shelf + 1));
  const atlas = canvas(AW, AH, g => items.forEach(it => g.drawImage(it.c, it.x, it.y)));
  const boxes = [];
  for (const [kind, v] of Object.entries(S.BOXES)) {
    if (Array.isArray(v)) boxes.push({ kind, variant: '', boxes: v.map(b => ({ ...b, top: b.top || '' })) });
    else for (const [vk, list] of Object.entries(v)) boxes.push({ kind, variant: vk, boxes: list.map(b => ({ ...b, top: b.top || '' })) });
  }
  return {
    png: atlas.toDataURL('image/png').split(',')[1],
    index: { width: AW, height: AH, sprites: items.map(it => ({ n: it.n, x: it.x, y: it.y, w: it.c.width, h: it.c.height, ax: it.ax, ay: it.ay, fy: it.fy })), shadowBoxes: boxes },
  };
});
await browser.close();
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'atlas.bytes'), Buffer.from(result.png, 'base64'));
fs.writeFileSync(path.join(out, 'atlasindex.json'), JSON.stringify(result.index));
console.log(`atlas ${result.index.width}x${result.index.height}, ${result.index.sprites.length} sprites`);
