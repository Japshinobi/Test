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

const PALETTES = JSON.parse(fs.readFileSync(path.join(root, 'godot/data/palette.json'), 'utf8'));
const result = await page.evaluate((PAL) => {
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

  /* палитры: земля, вода и всё, что в игре объёмное, — к палитре «3d», остальное (персонажи, растения, предметы) — к «2d».
     Каждый пиксель притягивается к ближайшему по восприятию цвету (Lab) своей палитры. */
  const IS_3D = /^(grass_|path_|site_|snow_|ice_|water_|trodden_|soil|field_|ditch_|cobbles_|bridge_|house|well|bin|mailbox|sign|barrier_|stall|tent_|fountain|rock|haystack|scarecrow)/;
  const lab = ([r, g, b]) => {
    const f = v => { v /= 255; return v > 0.04045 ? ((v + 0.055) / 1.055) ** 2.4 : v / 12.92; };
    const R = f(r), G = f(g), B = f(b);
    const X = (R * 0.4124 + G * 0.3576 + B * 0.1805) / 0.95047, Y = R * 0.2126 + G * 0.7152 + B * 0.0722, Z = (R * 0.0193 + G * 0.1192 + B * 0.9505) / 1.08883;
    const h = t => t > 0.008856 ? Math.cbrt(t) : 7.787 * t + 16 / 116;
    return [116 * h(Y) - 16, 500 * (h(X) - h(Y)), 200 * (h(Y) - h(Z))];
  };
  /* ряды палитры: цвет знает свой ряд и ступень (0 — самая светлая) */
  const ramps = {};
  for (const k of ['3d', '2d']) ramps[k] = Object.values(PAL[k]).map(r => r.map(hex => { const c = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16)); return {c, l: lab(c)}; }));
  const memo = {'3d': new Map(), '2d': new Map()};
  const nearest = (k, key) => {
    const m = memo[k];
    if (m.has(key)) return m.get(key);
    const L = lab([key >> 16, (key >> 8) & 255, key & 255]); let best = null, bd = Infinity;
    ramps[k].forEach((r, ri) => r.forEach((p, si) => { const d = (L[0] - p.l[0]) ** 2 + (L[1] - p.l[1]) ** 2 + (L[2] - p.l[2]) ** 2; if (d < bd) { bd = d; best = {ri, si, L0: L[0]}; } }));
    m.set(key, best); return best;
  };
  for (const it of items) {
    const k = IS_3D.test(it.n) ? '3d' : '2d';
    const g = it.c.getContext('2d'), im = g.getImageData(0, 0, it.c.width, it.c.height), d = im.data;
    /* какие цвета есть в рисунке и сколько их */
    const count = new Map();
    for (let i = 0; i < d.length; i += 4) if (d[i + 3]) { const key = (d[i] << 16) | (d[i + 1] << 8) | d[i + 2]; count.set(key, (count.get(key) || 0) + 1); }
    /* разные цвета рисунка, попавшие в одну ступень палитры, раздвигаем по ряду: светлее — выше, темнее — ниже,
       чтобы узор (камни, травинки, блики) не слился в одно пятно */
    const groups = new Map(), out = new Map();
    for (const key of count.keys()) { const n = nearest(k, key), gk = n.ri * 100 + n.si; if (!groups.has(gk)) groups.set(gk, []); groups.get(gk).push({key, n}); }
    for (const list of groups.values()) {
      const ramp = ramps[k][list[0].n.ri], si = list[0].n.si;
      if (list.length === 1) { out.set(list[0].key, ramp[si].c); continue; }
      list.sort((a, b) => count.get(b.key) - count.get(a.key));
      const main = list[0]; out.set(main.key, ramp[si].c);
      const lighter = list.slice(1).filter(e => e.n.L0 >= main.n.L0).sort((a, b) => a.n.L0 - b.n.L0);
      const darker = list.slice(1).filter(e => e.n.L0 < main.n.L0).sort((a, b) => b.n.L0 - a.n.L0);
      lighter.forEach((e, j) => out.set(e.key, ramp[Math.max(0, si - 1 - j)].c));
      darker.forEach((e, j) => out.set(e.key, ramp[Math.min(ramp.length - 1, si + 1 + j)].c));
    }
    for (let i = 0; i < d.length; i += 4) {
      if (!d[i + 3]) continue;
      const c = out.get((d[i] << 16) | (d[i + 1] << 8) | d[i + 2]);
      d[i] = c[0]; d[i + 1] = c[1]; d[i + 2] = c[2];
    }
    g.putImageData(im, 0, 0);
  }

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
}, PALETTES);
await browser.close();
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'atlas.png'), Buffer.from(result.png, 'base64'));
fs.writeFileSync(path.join(out, 'atlas.json'), JSON.stringify(result.index));
console.log(`atlas ${result.index.width}x${result.index.height}, ${result.index.sprites.length} sprites`);
