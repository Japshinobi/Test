// Собирает все рисунки из game/sprites.js в один атлас для игры на Godot: godot/assets/atlas.png + atlas.json.
// Запуск из корня репозитория:  node tools/export-atlas.mjs
// Нужны Node и Playwright с Chromium (PLAYWRIGHT_DIR — где лежит playwright, если он установлен глобально).
import fs from 'fs';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';
import { createRequire } from 'module';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const out = path.join(root, 'godot/assets');
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
  /* окрестности: поля, канава, брусчатка, мост */
  /* поля меняются и летом (пшеница зреет), поэтому для них летних видов 12 — по дню сезона */
  const fieldLooks = looks.filter(([ln]) => ln !== 'summer');
  for (let d = 1; d <= 12; d++) fieldLooks.push(['summer' + String(d).padStart(2, '0'), S.lookFor(12 + d, false)]);
  for (const [ln, L] of fieldLooks) for (const type of ['wheat', 'sun']) for (let i = 0; i < 4; i++)
    tile(`field_${type}_${ln}_${i}`, g => { g.translate(-i * T, -70 * T); S.drawField(g, i, 70, L, type); });
  for (let m = 0; m < 16; m++) for (const ice of [false, true]) tile(`ditch_${m}${ice ? '_ice' : ''}`, g => { g.translate(-5 * T, -70 * T); S.drawDitch(g, 5, 70, ice, m); });
  for (let i = 0; i < 4; i++) tile(`cobbles_${i}`, g => { g.translate(-i * T, -80 * T); S.drawCobbles(g, i, 80); });
  for (const side of [0, 1]) tile(`bridge_${side}`, g => S.drawBridge(g, 0, 0, side));
  for (const [sfx, L] of [['', SUMMER], ['_snow', SNOW]]) {
    S.clearCache();
    obj('barrier_h' + sfx, S.sprite('barrier', 'h', 0, L)); obj('barrier_v' + sfx, S.sprite('barrier', 'v', 0, L));
    for (const k of ['signpost', 'scarecrow', 'haystack', 'stallback']) obj(k + sfx, S.sprite(k, 0, 0, L));
    for (const who of ['fruit', 'veg', 'empty']) for (const open of [0, 1]) obj(`stall_${who}_${open}${sfx}`, S.sprite('stall', who, !!open, L));
    for (const who of ['berry', 'empty']) for (const open of [0, 1]) obj(`stallside_${who}_${open}${sfx}`, S.sprite('stallside', who, !!open, L));
    for (const open of [0, 1]) obj(`tent_any_${open}${sfx}`, S.sprite('tent', 'any', !!open, L));
    obj('fountain' + sfx, S.sprite('fountain', 0, 0, L));
  }
  for (let st = 0; st < 3; st++) obj(`sunflower_${st}`, S.sprite('sunflower', st, 0, SUMMER));
  /* торговцы отдельно от прилавков: в 3D-прилавке стоят спрайтом за стойкой (рисунок по пояс, точка опоры — низ) */
  for (const who of ['fruit', 'veg', 'berry', 'any']) add(`trader_${who}`, canvas(12, 17, g => S.drawTrader(S.painter(g, 0, 0), 1, 3, who, false)), 6, 17, 17);
  /* вода фонтана: 12 кадров по кругу (и замёрзшая) — рисуются поверх фонтана */
  const fo = S.sprite('fountain', 0, 0, SUMMER);
  for (let f = 0; f < 12; f++) add(`fountainwater_${f}`, canvas(48, 56, g => S.drawFountainWater(g, 0, 0, f * 2.222 / 12, false)), fo.ax, fo.ay, fo.fy);
  add('fountainwater_ice', canvas(48, 56, g => S.drawFountainWater(g, 0, 0, 0, true)), fo.ax, fo.ay, fo.fy);
  for (const k of ['hoe', 'can', 'axe', 'pick', 'scythe', 'wood', 'stone']) add('icon_' + k, S.iconCanvas(k));
  for (const k of Object.keys(S.CROPS)) { add('seed_' + k, S.iconCanvas('seed', k)); add('prod_' + k, S.iconCanvas('prod', k)); }

  /* shelf packing with 1 px of empty space around every sprite */
  items.sort((a, b) => b.c.height - a.c.height);
  const AW = 2048; let x = 1, y = 1, shelf = 0;
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
fs.writeFileSync(path.join(out, 'atlas.png'), Buffer.from(result.png, 'base64'));
fs.writeFileSync(path.join(out, 'atlas.json'), JSON.stringify(result.index));
console.log(`atlas ${result.index.width}x${result.index.height}, ${result.index.sprites.length} sprites`);
