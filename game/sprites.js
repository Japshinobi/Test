/* Дедушкин огород: все спрайты игры.
   Общий файл для игры (index.html) и каталога графики (catalog.html).
   Черновая клетка 16x16 пикселей (в игре растягивается до 32x32); каждая функция рисует пиксели прямоугольниками.
   Объекты (деревья, постройки, растения, персонаж) могут выходить за свою клетку вверх и в стороны. */
window.OgorodSprites = (() => {
'use strict';
const T = 16;

const C = {
  grass:'#33a532', grassD:'#22802a', grassL:'#62d04e', farm:'#976b4b', farmD:'#7a5236', farmL:'#b0835c',
  path:'#d6c27a', pathD:'#b9a35c', pathL:'#ecdc9c',
  water:'#2650d8', waterD:'#1a37a0', waterL:'#6a98f4',
  soil:'#6e4a30', soilD:'#553823', soilW:'#4a3020', soilWD:'#36220f',
  fence:'#a97c50', fenceD:'#6e4b2c', fenceL:'#c99a66',
  trunk:'#8a5a33', trunkD:'#5e3b1f', leaf:'#1fa31f', leafD:'#137013', leafL:'#4fd04f',
  stone:'#808080', stoneD:'#5a5a5a', stoneL:'#a6a6a6', ink:'#0b0e22', coin:'#ffd24a'
};

/* growth in game days; a season is 12 days. seasons: when it can grow (out of season it withers). regrow: days to the next harvest */
const CROPS = {
  radish:    {name:'Редис',     product:'Редис',     seedName:'Семена редиса',     seed:8,   sell:22,  grow:3,  seasons:['spring', 'autumn'], color:'#d8344a'},
  peas:      {name:'Горох',     product:'Горох',     seedName:'Семена гороха',     seed:20,  sell:14,  grow:6,  regrow:3, seasons:['spring'], color:'#8fd65a'},
  potato:    {name:'Картофель', product:'Картофель', seedName:'Семенной картофель',seed:15,  sell:55,  grow:8,  seasons:['spring'], color:'#c49a62'},
  carrot:    {name:'Морковь',   product:'Морковь',   seedName:'Семена моркови',    seed:20,  sell:80,  grow:10, seasons:['spring', 'autumn'], color:'#e8832a'},
  strawberry:{name:'Клубника',  product:'Клубника',  seedName:'Рассада клубники',  seed:40,  sell:30,  grow:8,  regrow:4, seasons:['spring', 'summer'], color:'#d63b45'},
  cucumber:  {name:'Огурец',    product:'Огурцы',    seedName:'Семена огурцов',    seed:15,  sell:12,  grow:5,  regrow:2, seasons:['summer'], color:'#3f9a3a'},
  tomato:    {name:'Помидор',   product:'Помидоры',  seedName:'Рассада томатов',   seed:25,  sell:24,  grow:7,  regrow:3, seasons:['summer'], color:'#e0402c'},
  corn:      {name:'Кукуруза',  product:'Кукуруза',  seedName:'Семена кукурузы',   seed:20,  sell:75,  grow:8,  seasons:['summer'], color:'#f2d14a'},
  pumpkin:   {name:'Тыква',     product:'Тыква',     seedName:'Семена тыквы',      seed:50,  sell:240, grow:11, seasons:['summer', 'autumn'], color:'#e98a1f'},
  apple:     {name:'Яблоня',    product:'Яблоки',    seedName:'Саженец яблони',    seed:200, sell:40,  grow:12, regrow:3, yield:3, tree:true,
              seasons:['spring', 'summer', 'autumn', 'winter'], plant:['spring', 'summer', 'autumn'], fruit:['autumn'], color:'#cf2f2f'}
};

function hash(a, b, c = 0) {
  let h = Math.imul(a | 0, 374761393) ^ Math.imul(b | 0, 668265263) ^ Math.imul(c | 0, 1274126177);
  h = Math.imul(h ^ (h >>> 13), 1274126177); h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

/* ---------- pixel drawing ---------- */
const painter = (g, X, Y) => (x, y, w, h, c) => { g.fillStyle = c; g.fillRect(X + x, Y + y, w, h); };

function drawGrass(g, x, y, pal = [C.grass, C.grassD, C.grassL]) {
  const P = painter(g, x * T, y * T);
  P(0, 0, 16, 16, pal[0]);
  for (let i = 0; i < 6; i++) P(Math.floor(hash(x, y, i) * 15), Math.floor(hash(x, y, i + 20) * 14), 1, 2, i % 2 ? pal[1] : pal[2]);
}
/* snow on the ground */
function drawSnow(g, x, y) {
  const P = painter(g, x * T, y * T);
  P(0, 0, 16, 16, '#eef3fb');
  for (let i = 0; i < 6; i++) P(Math.floor(hash(x, y, i + 90) * 15), Math.floor(hash(x, y, i + 95) * 15), 2, 1, i % 3 ? '#d6e1f2' : '#ffffff');
}
/* trodden snow: the ground shows through, snow stays at the edges */
function drawTrodden(g, x, y) {
  const P = painter(g, x * T, y * T);
  for (let i = 0; i < 14; i++) {
    const e = Math.floor(hash(x, y, i + 120) * 4), t = Math.floor(hash(x, y, i + 140) * 14);
    const [px, py] = [[t, 0], [t, 14], [0, t], [14, t]][e];
    P(px, py, 2, 2, i % 3 ? '#e4ebf6' : '#ffffff');
  }
  P(5, 4, 2, 3, 'rgba(90,110,140,.25)'); P(9, 9, 2, 3, 'rgba(90,110,140,.25)');
}
/* building site: packed earth, ready for a future building */
function drawSite(g, x, y) {
  const P = painter(g, x * T, y * T);
  P(0, 0, 16, 16, '#a07a52');
  for (let i = 0; i < 6; i++) P(Math.floor(hash(x, y, i + 210) * 15), Math.floor(hash(x, y, i + 220) * 15), 1, 1, i % 2 ? '#86623e' : '#b8946a');
}
/* someone else's fields at the crossroads; they change with the seasons. type: 'wheat' or 'sun' (sunflowers) */
function drawField(g, x, y, look, type) {
  const P = painter(g, x * T, y * T), t = (look.d - 1) / 11, h = (i, s) => hash(x, y, i + s);
  if (look.season === 'winter') {
    P(0, 0, 16, 16, '#8a7a6a'); for (let r = 2; r < 16; r += 4) P(0, r, 16, 1, '#6e604f');
    return;
  }
  if (look.season === 'spring' || (type === 'sun' && look.season === 'summer' && t < .2)) {
    P(0, 0, 16, 16, '#7a5236'); for (let r = 2; r < 16; r += 4) P(0, r, 16, 1, '#5e3e26');
    const n = look.season === 'spring' ? Math.round(t * 8) : 8;
    for (let i = 0; i < n; i++) P(Math.floor(h(i, 230) * 15), 1 + 4 * Math.floor(h(i, 240) * 4), 1, 2, i % 2 ? '#62d04e' : '#3fb83a');
    return;
  }
  if (look.season === 'autumn') {
    P(0, 0, 16, 16, type === 'sun' ? '#8a7a4a' : '#c2a35a');
    for (let i = 0; i < 12; i++) P(Math.floor(h(i, 250) * 15), Math.floor(h(i, 260) * 14), 1, 2, type === 'sun' ? '#5e4a2a' : '#9a7a3a');
    return;
  }
  /* summer */
  if (type === 'sun') { P(0, 0, 16, 16, '#3f8a2f'); for (let i = 0; i < 6; i++) P(Math.floor(h(i, 270) * 14), Math.floor(h(i, 280) * 14), 3, 2, '#5aa83a'); return; }
  const ripe = t > .45, stalk = ripe ? '#d9b84a' : '#6fbf3a', head = ripe ? '#f0d878' : '#9ad85a', base = ripe ? '#c9a23a' : '#4f9a2f';
  P(0, 0, 16, 16, base);
  for (let c = 0; c < 16; c += 2) {
    const top = 1 + Math.floor(h(c, 290) * 4);
    P(c, top + 2, 1, 14 - top, stalk); P(c, top, 1, 3, head);
  }
}
/* a ditch with water and reeds: a natural edge of the walkable world.
   mask tells which neighbours are ditch too (1 left, 2 right, 4 up, 8 down), so it runs on and turns corners */
function drawDitch(g, x, y, ice, mask = 3) {
  const P = painter(g, x * T, y * T), bank = '#5e4a2e', water = ice ? '#b9dcf2' : '#2f5fb8', hi = ice ? '#ffffff' : '#6a98f4';
  if (!(mask & 12) && !(mask & 3)) mask = 3;
  P(0, 0, 16, 16, '#4f7a36');
  P(3, 3, 10, 10, bank);
  if (mask & 1) P(0, 3, 8, 10, bank); if (mask & 2) P(8, 3, 8, 10, bank); if (mask & 4) P(3, 0, 10, 8, bank); if (mask & 8) P(3, 8, 10, 8, bank);
  P(5, 5, 6, 6, water);
  if (mask & 1) P(0, 5, 8, 6, water); if (mask & 2) P(8, 5, 8, 6, water); if (mask & 4) P(5, 0, 6, 8, water); if (mask & 8) P(5, 8, 6, 8, water);
  if (mask & 3) P(mask & 1 ? 0 : 5, 5, (mask & 1 ? 8 : 3) + (mask & 2 ? 8 : 3), 1, hi); else P(5, mask & 4 ? 0 : 5, 1, (mask & 4 ? 8 : 3) + (mask & 8 ? 8 : 3), hi);
  for (let i = 0; i < 3; i++) {
    const r = Math.floor(hash(x, y, i + 300) * 3);
    const [rx, ry] = (mask & 3) && !(mask & 12) ? [Math.floor(hash(x, y, i + 310) * 14), i % 2 ? 0 : 12] : [i % 2 ? 0 : 14, Math.floor(hash(x, y, i + 310) * 12)];
    P(rx, ry, 1, 3 + r, '#3f8a2f'); P(rx, ry, 1, 1, '#8a6a3a');
  }
}
/* market square cobbles */
function drawCobbles(g, x, y) {
  const P = painter(g, x * T, y * T);
  P(0, 0, 16, 16, '#a8a294');
  for (let r = 0; r < 4; r++) for (let c = 0; c < 2; c++) {
    const ox = (r % 2) * 4 + c * 8;
    P(ox + 1, r * 4 + 1, 6, 3, hash(x * 4 + c, y * 4 + r, 310) < .5 ? '#bdb6a6' : '#b2ab9b');
  }
}
/* wooden bridge planks over the river; side: 0 left half, 1 right half */
function drawBridge(g, x, y, side) {
  const P = painter(g, x * T, y * T);
  P(0, 0, 16, 16, '#a97c50');
  for (let r = 3; r < 16; r += 4) P(0, r, 16, 1, '#6e4b2c');
  if (side === 0) { P(0, 0, 2, 16, '#6e4b2c'); P(0, 0, 1, 16, '#c99a66'); } else { P(14, 0, 2, 16, '#6e4b2c'); P(15, 0, 1, 16, '#c99a66'); }
}
/* fallen leaves lying on the grass in autumn */
function drawFallen(g, x, y, amount) {
  const P = painter(g, x * T, y * T), cols = ['#e0a02a', '#d9662a', '#f5d04a', '#a8601a'], n = Math.round(amount * 5);
  for (let i = 0; i < n; i++) P(Math.floor(hash(x, y, i + 160) * 14), Math.floor(hash(x, y, i + 170) * 14), 2, 1, cols[Math.floor(hash(x, y, i + 180) * 4)]);
}
function drawPath(g, x, y) {
  const P = painter(g, x * T, y * T);
  P(0, 0, 16, 16, C.path);
  for (let i = 0; i < 5; i++) P(Math.floor(hash(x, y, i + 3) * 14), Math.floor(hash(x, y, i + 30) * 14), 2, 1, i % 2 ? C.pathD : C.pathL);
}
function drawFlowers(g, x, y) { drawGrass(g, x, y); drawFlowerDots(g, x * T, y * T, x, y); }
/* mode: 'bloom' in spring, 'some' in summer, 'wither' in autumn */
function drawFlowerDots(g, X, Y, x, y, mode = 'some') {
  const P = painter(g, X, Y);
  if (mode === 'wither') {
    for (let i = 0; i < 2; i++) {
      const fx = 2 + Math.floor(hash(x, y, i + 40) * 11), fy = 2 + Math.floor(hash(x, y, i + 50) * 11);
      P(fx + 1, fy + 1, 1, 3, '#8a7a3a'); P(fx, fy, 3, 2, '#a08a5a');
    }
    return;
  }
  if (mode === 'bloom') {
    const cols = ['#ffffff', '#f5d33b', '#ff8fc0', '#b48cf0'];
    for (let i = 0; i < 4; i++) {
      const fx = 1 + Math.floor(hash(x, y, i + 40) * 12), fy = 1 + Math.floor(hash(x, y, i + 50) * 12);
      P(fx, fy, 3, 3, cols[Math.floor(hash(x, y, i + 60) * 4)]); P(fx + 1, fy + 1, 1, 1, '#c8922a');
    }
    return;
  }
  const cols = ['#f4f1e8', '#f5d33b', '#e88bb5'];
  for (let i = 0; i < 2; i++) {
    const fx = 2 + Math.floor(hash(x, y, i + 40) * 11), fy = 2 + Math.floor(hash(x, y, i + 50) * 11);
    P(fx, fy, 3, 3, cols[Math.floor(hash(x, y, i + 60) * 3)]); P(fx + 1, fy + 1, 1, 1, '#c8922a');
  }
}
function drawDirt(g, x, y) {
  const P = painter(g, x * T, y * T);
  P(0, 0, 16, 16, C.farm);
  for (let i = 0; i < 7; i++) P(Math.floor(hash(x, y, i + 70) * 15), Math.floor(hash(x, y, i + 80) * 15), 2, 1, i % 2 ? C.farmD : C.farmL);
}
function decoKind(x, y) { const r = hash(x, y, 9); return r < 0.35 ? 0 : r < 0.7 ? 1 : 2; }
function drawLocked(g, x, y) { drawGrass(g, x, y); drawDeco(g, x * T, y * T, decoKind(x, y)); }
/* overgrowth on uncleared land: 0 stone, 1 weeds, 2 stump. Weeds change colour with the season */
const WEED = {spring:'#2f9e3a', summer:C.leafD, autumn:'#8a7a2a', winter:'#7a6a4a'};
function drawDeco(g, X, Y, v, season = 'summer') {
  const P = painter(g, X, Y), wd = WEED[season];
  if (v === 0) { P(4, 6, 7, 5, C.stone); P(4, 6, 7, 1, C.stoneL); P(5, 10, 6, 1, C.stoneD); }
  else if (v === 1) { P(3, 4, 1, 6, wd); P(5, 2, 1, 8, wd); P(7, 5, 1, 5, wd); P(10, 7, 1, 5, wd); P(12, 5, 1, 6, wd); }
  else { P(5, 8, 6, 5, C.trunk); P(5, 8, 6, 2, '#a0784f'); P(7, 8, 2, 1, C.trunkD); }
}
function fenceMask(x, y, is) { return (is(x - 1, y) ? 1 : 0) | (is(x + 1, y) ? 2 : 0) | (is(x, y - 1) ? 4 : 0) | (is(x, y + 1) ? 8 : 0); }
function drawFence(g, x, y, is) { drawGrass(g, x, y); drawFencePiece(g, x * T, y * T, fenceMask(x, y, is)); }
/* one fence section; mask says which neighbours it joins: 1 left, 2 right, 4 up, 8 down */
function drawFencePiece(g, X, Y, m) {
  const P = painter(g, X, Y);
  if (m & 1) { P(0, 6, 8, 2, C.fence); P(0, 10, 8, 2, C.fence); }
  if (m & 2) { P(8, 6, 8, 2, C.fence); P(8, 10, 8, 2, C.fence); }
  if (m & 4) P(7, 0, 2, 6, C.fence);
  if (m & 8) P(7, 12, 2, 4, C.fence);
  P(5, 3, 6, 11, C.fence); P(5, 3, 6, 1, C.fenceL); P(5, 13, 6, 1, C.fenceD); P(10, 4, 1, 9, C.fenceD);
}
function drawTree(g, v = 0) { drawTreeWood(g, v); drawTreeCanopy(g, v); }
const line = (P, x0, y0, x1, y1, w, c) => {
  const n = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0)) || 1;
  for (let i = 0; i <= n; i++) P(Math.round(x0 + (x1 - x0) * i / n), Math.round(y0 + (y1 - y0) * i / n), w, 1, c);
};
/* trunk and bare branches: what is left when the leaves fall */
function drawTreeWood(g, v = 0) {
  const P = painter(g, 0, 0);
  if (v === 1) {
    line(P, 15, 24, 15, 4, 2, C.trunk); line(P, 15, 18, 8, 8, 1, C.trunk); line(P, 16, 15, 23, 6, 1, C.trunk);
    line(P, 15, 10, 10, 3, 1, C.trunk); line(P, 16, 9, 21, 2, 1, C.trunk); line(P, 15, 20, 22, 14, 1, C.trunk);
    P(14, 23, 4, 17, C.trunk); P(14, 23, 1, 17, C.trunkD); P(12, 38, 8, 2, C.trunk);
    return;
  }
  line(P, 15, 28, 7, 12, 2, C.trunk); line(P, 17, 28, 25, 11, 2, C.trunk); line(P, 16, 27, 16, 5, 2, C.trunk);
  line(P, 9, 16, 4, 12, 1, C.trunk); line(P, 23, 15, 28, 12, 1, C.trunk); line(P, 16, 12, 11, 5, 1, C.trunk);
  line(P, 16, 12, 21, 4, 1, C.trunk); line(P, 8, 13, 9, 7, 1, C.trunk); line(P, 24, 13, 23, 6, 1, C.trunk);
  P(13, 27, 6, 13, C.trunk); P(13, 27, 2, 13, C.trunkD); P(11, 38, 10, 2, C.trunk); P(11, 38, 2, 2, C.trunkD);
}
function drawTreeCanopy(g, v = 0) {
  const P = painter(g, 0, 0);
  if (v === 1) {
    P(8, 3, 16, 20, C.leaf); P(6, 8, 20, 12, C.leaf); P(11, 1, 10, 2, C.leaf); P(10, 23, 12, 2, C.leaf);
    P(6, 18, 20, 2, C.leafD); P(21, 6, 4, 13, C.leafD); P(10, 24, 12, 1, C.leafD);
    P(10, 4, 5, 3, C.leafL); P(8, 9, 4, 4, C.leafL); P(14, 7, 3, 2, C.leafL);
    P(16, 12, 2, 1, C.leafD); P(11, 15, 2, 1, C.leafD); P(18, 9, 1, 2, C.leafD);
    return;
  }
  P(5, 8, 22, 15, C.leaf); P(3, 11, 26, 9, C.leaf); P(8, 4, 16, 5, C.leaf); P(11, 2, 10, 2, C.leaf);
  P(7, 22, 18, 4, C.leaf); P(10, 26, 12, 2, C.leaf);
  P(3, 18, 26, 2, C.leafD); P(7, 24, 18, 2, C.leafD); P(24, 10, 4, 9, C.leafD); P(10, 27, 12, 1, C.leafD);
  P(9, 5, 7, 3, C.leafL); P(6, 9, 6, 4, C.leafL); P(13, 8, 4, 2, C.leafL); P(5, 13, 3, 3, C.leafL);
  P(15, 13, 2, 1, C.leafD); P(20, 8, 1, 2, C.leafD); P(11, 16, 2, 1, C.leafD); P(19, 19, 2, 1, C.leafD);
}
function drawBush(g) { drawBushTwigs(g); drawBushLeaves(g); drawBerries(g); }
function drawBushTwigs(g) {
  const P = painter(g, 0, 0);
  line(P, 10, 15, 4, 5, 1, C.trunk); line(P, 10, 15, 10, 3, 1, C.trunk); line(P, 10, 15, 16, 5, 1, C.trunk); line(P, 7, 10, 3, 9, 1, C.trunk); line(P, 13, 10, 17, 8, 1, C.trunk);
}
function drawBerries(g) {
  const P = painter(g, 0, 0), r = '#d63b45';
  P(6, 7, 2, 2, r); P(12, 9, 2, 2, r); P(8, 11, 2, 2, r); P(6, 7, 1, 1, '#f07070'); P(12, 9, 1, 1, '#f07070');
}
function drawBushLeaves(g) {
  const P = painter(g, 0, 0);
  P(3, 4, 14, 10, C.leaf); P(1, 6, 18, 7, C.leaf); P(5, 2, 10, 2, C.leaf);
  P(6, 3, 5, 2, C.leafL); P(3, 6, 3, 2, C.leafL); P(2, 12, 16, 2, C.leafD); P(15, 6, 2, 6, C.leafD);
}
function drawWell(g) {
  const P = painter(g, 0, 0);
  P(2, 4, 2, 15, C.trunk); P(12, 4, 2, 15, C.trunk); P(2, 4, 1, 15, C.trunkD);
  P(0, 1, 16, 4, '#7a4a26'); P(2, 0, 12, 1, '#9a6a3a'); P(0, 4, 16, 1, '#5a3418');
  P(4, 6, 8, 1, C.trunkD); P(7, 7, 1, 7, '#d9c9a0');
  P(1, 18, 14, 10, C.stone); P(1, 18, 14, 2, C.stoneL); P(3, 19, 10, 2, '#2a4f78');
  P(3, 23, 3, 1, C.stoneD); P(9, 25, 3, 1, C.stoneD); P(6, 22, 2, 1, C.stoneD); P(12, 22, 2, 1, C.stoneD); P(1, 27, 14, 1, C.stoneD);
  P(6, 13, 4, 4, '#8b8b8b'); P(6, 13, 4, 1, '#b0b0b0');
}
/* shipping bin: produce put in it is paid for the next morning */
function drawBin(g) {
  const P = painter(g, 0, 0);
  P(1, 6, 14, 10, '#8a5a33'); P(1, 6, 1, 10, '#a97c50'); P(14, 6, 1, 10, '#5e3b1f');
  P(1, 10, 14, 1, '#5e3b1f'); P(1, 15, 14, 1, '#4b2e17');
  P(0, 3, 16, 4, '#a97c50'); P(0, 3, 16, 1, '#c99a66'); P(0, 6, 16, 1, '#6e4b2c');
  P(3, 3, 2, 13, '#6f6f66'); P(11, 3, 2, 13, '#6f6f66'); P(7, 7, 2, 2, '#ffd24a');
}
/* mailbox: the seed catalogue arrives by post */
function drawMailbox(g) {
  const P = painter(g, 0, 0);
  P(5, 9, 2, 13, C.trunk); P(5, 9, 1, 13, C.trunkD); P(3, 20, 6, 2, C.trunk);
  P(1, 2, 10, 7, '#3d6fd6'); P(2, 1, 8, 1, '#3d6fd6'); P(1, 2, 10, 1, '#6f98f0'); P(1, 8, 10, 1, '#284a9a');
  P(3, 5, 6, 1, '#1c2f6a'); P(10, 1, 1, 6, '#f0bf45'); P(11, 1, 2, 2, '#e0402c');
}
/* corner stake of a building site, with a red ribbon */
function drawStake(g) {
  const P = painter(g, 0, 0);
  P(2, 2, 2, 12, C.trunk); P(2, 2, 1, 12, C.trunkD); P(1, 1, 4, 2, '#c99a66'); P(4, 4, 3, 2, '#e0402c'); P(5, 6, 2, 1, '#b8301e');
}
/* boulder: the pickaxe breaks it */
function drawRock(g) {
  const P = painter(g, 0, 0);
  P(2, 4, 12, 8, C.stone); P(3, 2, 9, 3, C.stone); P(4, 1, 6, 1, C.stone);
  P(3, 2, 6, 2, C.stoneL); P(2, 5, 2, 3, C.stoneL); P(2, 10, 12, 2, C.stoneD); P(11, 3, 3, 8, C.stoneD);
  P(6, 6, 2, 1, C.stoneD); P(8, 8, 1, 1, C.stoneD); P(5, 9, 1, 1, C.stoneL);
}
/* fallen branches: one blow of the axe */
function drawTwigs(g) {
  const P = painter(g, 0, 0);
  line(P, 1, 6, 12, 2, 1, C.trunk); line(P, 3, 7, 14, 5, 1, C.trunkD); line(P, 6, 4, 8, 1, 1, C.trunk); line(P, 10, 5, 12, 7, 1, C.trunk);
  P(12, 1, 2, 1, C.leafD); P(7, 0, 2, 1, C.leaf);
}
/* what is left of a felled tree */
function drawStump(g) {
  const P = painter(g, 0, 0);
  P(3, 3, 10, 7, C.trunk); P(3, 3, 2, 7, C.trunkD); P(3, 2, 10, 2, '#c99a66'); P(5, 2, 6, 1, '#a0784f'); P(7, 2, 2, 1, C.trunkD);
  P(1, 8, 3, 2, C.trunk); P(12, 8, 3, 2, C.trunk);
}
/* a huge old oak blocking the road for now; 48 × 64 */
function drawBigTree(g, look) {
  const P = painter(g, 0, 0);
  line(P, 23, 40, 8, 18, 3, C.trunk); line(P, 25, 40, 40, 16, 3, C.trunk); line(P, 24, 38, 24, 8, 3, C.trunk);
  line(P, 12, 24, 4, 20, 1, C.trunk); line(P, 36, 22, 45, 18, 1, C.trunk); line(P, 24, 18, 16, 6, 1, C.trunk); line(P, 25, 18, 33, 6, 1, C.trunk);
  P(19, 38, 11, 24, C.trunk); P(19, 38, 3, 24, C.trunkD); P(27, 40, 2, 20, '#a97c50'); P(15, 58, 19, 6, C.trunk); P(13, 61, 4, 3, C.trunkD); P(32, 61, 4, 3, C.trunkD);
  P(22, 46, 4, 5, '#3a2414');
}
function drawBigCanopy(g) {
  const P = painter(g, 0, 0);
  P(6, 8, 36, 30, C.leaf); P(2, 14, 44, 20, C.leaf); P(12, 3, 24, 6, C.leaf); P(16, 1, 16, 2, C.leaf); P(8, 37, 32, 5, C.leaf);
  P(2, 30, 44, 3, C.leafD); P(36, 12, 8, 18, C.leafD); P(10, 39, 28, 3, C.leafD);
  P(12, 5, 12, 4, C.leafL); P(6, 12, 8, 6, C.leafL); P(18, 10, 6, 3, C.leafL); P(4, 20, 4, 5, C.leafL);
  P(22, 18, 2, 2, C.leafD); P(30, 14, 2, 3, C.leafD); P(14, 24, 3, 2, C.leafD); P(28, 26, 3, 2, C.leafD);
}
/* striped barrier: across a vertical road (h, 32 × 18) or a horizontal one (v, 14 × 36) */
function drawBarrier(g, dir) {
  const P = painter(g, 0, 0), R = '#d6455a', Wt = '#f2e6bf';
  if (dir === 'h') {
    P(1, 4, 3, 14, '#5a5a5a'); P(28, 8, 3, 10, '#5a5a5a');
    for (let i = 0; i < 6; i++) P(2 + i * 5, 6, 5, 3, i % 2 ? Wt : R);
    P(2, 9, 29, 1, 'rgba(0,0,0,.25)');
    return;
  }
  P(5, 0, 4, 4, '#5a5a5a'); P(5, 30, 4, 6, '#5a5a5a');
  for (let i = 0; i < 6; i++) P(5, 3 + i * 5, 3, 5, i % 2 ? Wt : R);
  P(8, 3, 1, 28, 'rgba(0,0,0,.25)');
}
/* signpost with arrows, 18 × 26 */
function drawSignpost(g) {
  const P = painter(g, 0, 0), wd = '#a97c50', dk = '#6e4b2c';
  P(8, 4, 2, 22, C.trunk); P(8, 4, 1, 22, C.trunkD);
  P(2, 4, 12, 4, wd); P(14, 5, 2, 2, wd); P(2, 7, 12, 1, dk);
  P(4, 10, 12, 4, wd); P(2, 11, 2, 2, wd); P(4, 13, 12, 1, dk);
  P(3, 16, 11, 4, wd); P(14, 17, 2, 2, wd); P(3, 19, 11, 1, dk);
  P(4, 5, 6, 1, '#5e3b1f'); P(7, 11, 6, 1, '#5e3b1f'); P(5, 17, 6, 1, '#5e3b1f'); P(8, 2, 2, 2, C.trunk);
}
/* scarecrow, 16 × 28 */
function drawScarecrow(g) {
  const P = painter(g, 0, 0);
  P(7, 8, 2, 20, C.trunk); P(1, 12, 14, 2, C.trunk);
  P(4, 11, 8, 9, '#5b8fd6'); P(4, 11, 8, 1, '#7fa8e6'); P(2, 12, 3, 3, '#5b8fd6'); P(11, 12, 3, 3, '#5b8fd6'); P(6, 14, 1, 1, '#f0bf45'); P(9, 16, 1, 1, '#f0bf45');
  P(1, 14, 2, 2, '#e3c069'); P(13, 14, 2, 2, '#e3c069'); P(5, 20, 6, 2, '#e3c069');
  P(5, 3, 6, 6, '#e8d6a8'); P(6, 5, 1, 1, C.ink); P(9, 5, 1, 1, C.ink); P(6, 7, 4, 1, '#8a6a3a');
  P(3, 2, 10, 2, '#9c6b2f'); P(5, 0, 6, 2, '#9c6b2f');
}
/* sunflower in the field. stage: 0 young, 1 bloom, 2 dry (autumn) */
function drawSunflower(g, stage) {
  const P = painter(g, 0, 0);
  if (stage === 2) {
    P(6, 8, 2, 18, '#8a7a3a'); P(3, 14, 3, 2, '#7a6a3a'); P(8, 17, 3, 2, '#7a6a3a');
    P(4, 6, 6, 5, '#5e4a2a'); P(5, 10, 4, 1, '#8a6a3a');
    return;
  }
  if (stage === 0) { P(6, 12, 2, 14, '#5aa83a'); P(3, 15, 3, 3, C.leaf); P(8, 13, 3, 3, C.leaf); P(5, 10, 4, 3, '#7ad04a'); return; }
  P(6, 9, 2, 17, '#4f9a2f'); P(2, 14, 4, 3, C.leaf); P(8, 17, 4, 3, C.leaf); P(2, 14, 2, 1, C.leafL);
  P(2, 1, 10, 9, '#f5c518'); P(1, 3, 12, 5, '#f5c518'); P(4, 0, 6, 1, '#f5c518'); P(4, 9, 6, 1, '#f5c518');
  P(4, 3, 6, 5, '#6b3e1a'); P(5, 4, 2, 2, '#8a5a2a'); P(2, 2, 2, 1, '#ffe066');
}
/* haystack after the harvest, 24 × 18 */
function drawHaystack(g) {
  const P = painter(g, 0, 0);
  P(2, 8, 20, 10, '#d9b84a'); P(4, 4, 16, 5, '#d9b84a'); P(7, 1, 10, 4, '#e8cc6a'); P(10, 0, 4, 1, '#e8cc6a');
  P(2, 16, 20, 2, '#a8862a'); P(18, 6, 4, 10, '#b8962a');
  for (let i = 0; i < 7; i++) P(4 + i * 2.5 | 0, 6 + (i % 3) * 3, 1, 3, '#f0dc8a');
}
/* ---------- market ---------- */
/* a trader: 10 × 14, standing behind a counter. who: 'fruit', 'veg', 'berry', 'any' */
const TRADER = {
  fruit:{skin:'#f0c29a', hair:'#8a8a8a', top:'#3f8a3a', apron:'#f2e6bf', hat:null, beard:true},
  veg:  {skin:'#f0c29a', hair:'#7a4a22', top:'#5b8fd6', apron:'#f2e6bf', hat:'#d6455a', beard:false},
  berry:{skin:'#f5d0b0', hair:'#c0563a', top:'#9a4ad6', apron:'#ffd6e8', hat:null, beard:false, braid:true},
  any:  {skin:'#d9a27a', hair:'#2b1f16', top:'#6b4627', apron:null, hat:'#3a3a5a', beard:true}
};
function drawTrader(P, ox, oy, who, side) {
  const t = TRADER[who];
  P(ox + 1, oy + 7, 8, 7, t.top); if (t.apron) P(ox + 3, oy + 8, 4, 6, t.apron);
  P(ox + 2, oy, 6, 7, t.skin);
  if (side) { P(ox + 6, oy + 3, 1, 1, C.ink); P(ox + 2, oy, 3, 4, t.hair); }
  else { P(ox + 3, oy + 3, 1, 1, C.ink); P(ox + 6, oy + 3, 1, 1, C.ink); P(ox + 2, oy, 6, 2, t.hair); }
  if (t.beard) P(ox + 2, oy + 5, 6, 2, t.hair);
  if (t.braid) P(ox + 7, oy + 2, 2, 7, t.hair);
  if (t.hat) { P(ox + 1, oy - 1, 8, 2, t.hat); P(ox + 2, oy - 3, 6, 2, t.hat); }
}
/* goods laid out on a counter */
function drawGoods(P, x, y, who, n) {
  const sets = {fruit:['#cf2f2f', '#8fd65a', '#f2d14a'], veg:['#e8832a', '#3f9a3a', '#e0402c', '#c49a62'], berry:['#d63b45', '#8a5a33', '#9a4ad6'], any:['#efe0b4', '#c99a66', '#efe0b4']}[who];
  for (let i = 0; i < n; i++) { P(x + i * 6, y, 5, 4, '#7a5230'); P(x + i * 6 + 1, y - 1, 3, 2, sets[i % sets.length]); P(x + i * 6 + 2, y - 2, 1, 1, sets[(i + 1) % sets.length]); }
}
const AWNING = {fruit:['#c7432f', '#f2e6bf'], veg:['#3f8a3a', '#f2e6bf'], berry:['#7a3aa8', '#f2e6bf'], any:['#5a3a8a', '#ffd24a'], empty:['#8a7a6a', '#b8ab98']};
/* stall facing down, 64 × 48 (4 × 3 tiles). Closed or empty: shutters down, nobody inside */
function drawStall(g, who, open) {
  const P = painter(g, 0, 0), [a1, a2] = AWNING[who];
  P(2, 12, 60, 22, '#8b6a45'); for (let x = 2; x < 62; x += 8) P(x, 12, 1, 22, '#6f5235');
  P(2, 10, 4, 38, C.fenceD); P(58, 10, 4, 38, C.fenceD);
  for (let i = 0; i < 8; i++) { const c = i % 2 ? a2 : a1; P(i * 8, 0, 8, 10, c); P(i * 8 + 1, 10, 6, 2, c); P(i * 8 + 2, 12, 4, 1, c); }
  P(0, 0, 64, 1, '#3a2a1f');
  if (open && who !== 'empty') drawTrader(P, 27, 16, who, false);
  else { P(6, 14, 52, 16, '#6f5235'); for (let y = 16; y < 30; y += 3) P(6, y, 52, 1, '#5a4228'); }
  P(0, 30, 64, 18, C.fence); P(0, 30, 64, 3, C.fenceL); P(0, 39, 64, 1, C.fenceD); P(0, 46, 64, 2, C.fenceD);
  if (open && who !== 'empty') { drawGoods(P, 4, 28, who, 3); drawGoods(P, 42, 28, who, 3); }
  if (who === 'empty') { P(22, 36, 20, 7, '#f2e6bf'); P(24, 38, 16, 1, '#8a6a3a'); P(24, 40, 12, 1, '#8a6a3a'); }
}
/* stall on the left side of the square, facing right: 48 × 64 (3 × 4 tiles) */
function drawStallSide(g, who, open) {
  const P = painter(g, 0, 0), [a1, a2] = AWNING[who];
  P(0, 4, 12, 56, '#8b6a45'); for (let y = 4; y < 60; y += 8) P(0, y, 12, 1, '#6f5235');
  for (let i = 0; i < 8; i++) P(0, 2 + i * 7, 18, 7, i % 2 ? a2 : a1);
  P(18, 2, 2, 56, '#3a2a1f');
  if (open && who !== 'empty') drawTrader(P, 20, 24, who, true);
  P(32, 12, 14, 50, C.fence); P(32, 12, 3, 50, C.fenceL); P(44, 12, 2, 50, C.fenceD); P(32, 60, 14, 2, C.fenceD);
  if (open && who !== 'empty') for (let i = 0; i < 4; i++) { P(35, 16 + i * 11, 8, 6, '#7a5230'); P(36, 15 + i * 11, 6, 3, {berry:['#d63b45', '#8a5a33'], fruit:['#cf2f2f', '#8fd65a'], veg:['#e8832a', '#3f9a3a'], any:['#efe0b4', '#c99a66']}[who][i % 2]); }
  P(2, 58, 4, 6, C.fenceD); P(40, 58, 4, 6, C.fenceD);
}
/* back of a stall on the bottom row of the square (a free place for a future trader), 64 × 40 */
function drawStallBack(g) {
  const P = painter(g, 0, 0), [a1, a2] = AWNING.empty;
  for (let i = 0; i < 8; i++) P(i * 8, 0, 8, 14, i % 2 ? a2 : a1);
  P(0, 14, 64, 2, '#3a2a1f');
  P(2, 16, 60, 22, '#8b6a45'); for (let x = 2; x < 62; x += 8) P(x, 16, 1, 22, '#6f5235'); P(2, 36, 60, 2, '#5a4228');
  P(2, 16, 4, 24, C.fenceD); P(58, 16, 4, 24, C.fenceD);
}
/* the universal trader's tent in the middle of the square, 64 × 64 */
function drawTent(g, open) {
  const P = painter(g, 0, 0), [a1, a2] = AWNING.any;
  for (let r = 0; r < 26; r++) { const w = 8 + r * 2; for (let x = 0; x < w; x++) P(32 - w / 2 + x, r + 2, 1, 1, Math.floor((x - w / 2) / Math.max(2, w / 8) + 8) % 2 ? a2 : a1); }
  P(31, 0, 2, 3, '#3a2a1f'); P(33, 0, 4, 2, '#ffd24a');
  P(4, 28, 56, 26, a1); for (let x = 4; x < 60; x += 8) P(x, 28, 4, 26, a2);
  P(18, 30, 28, 24, open ? '#2a1c3a' : a1);
  if (open) { P(16, 30, 4, 24, '#7a5aa8'); P(44, 30, 4, 24, '#7a5aa8'); drawTrader(P, 27, 34, 'any', false); }
  P(10, 50, 44, 10, C.fence); P(10, 50, 44, 2, C.fenceL); P(10, 58, 44, 2, C.fenceD);
  if (open) drawGoods(P, 13, 49, 'any', 6);
  P(4, 54, 3, 10, C.fenceD); P(57, 54, 3, 10, C.fenceD);
}
/* round fountain seen from above at an angle: an oval basin with a visible front wall, 48 × 56
   (stands on 3 × 3 tiles, the spout rises above). The water is drawn every frame by drawFountainWater */
const FC = {cx:24, cy:37, rx:23, ry:12, wall:5, irx:19, iry:9};
const ell = (P, cx, cy, rx, ry, col, from = -ry, to = ry) => {
  for (let y = from; y <= to; y++) { const w = Math.round(rx * Math.sqrt(Math.max(0, 1 - (y / ry) ** 2))); if (w > 0) P(cx - w, cy + y, w * 2, 1, col); }
};
function drawFountain(g) {
  const P = painter(g, 0, 0), {cx, cy, rx, ry, wall, irx, iry} = FC;
  /* front wall: the lower half of the oval pushed down */
  for (let d = wall; d > 0; d--) ell(P, cx, cy + d, rx, ry, d === wall ? '#5f5f57' : C.stoneD, 0, ry);
  ell(P, cx, cy, rx, ry, C.stone);
  ell(P, cx, cy, rx, ry, C.stoneL, -ry, -ry + 2);
  ell(P, cx, cy + 1, irx, iry, '#2f6fd8');
  ell(P, cx, cy + 1, irx, iry, '#24589f', -iry, -iry + 1);
  /* pedestal and the top bowl */
  P(21, 18, 6, 20, C.stone); P(21, 18, 2, 20, C.stoneL); P(25, 18, 2, 20, C.stoneD);
  ell(P, cx, 19, 9, 3, C.stoneD, 0, 3); ell(P, cx, 17, 9, 3, C.stone); ell(P, cx, 17, 7, 2, '#2f6fd8');
}
function drawFountainWater(g, X, Y, sec, ice) {
  const P = painter(g, X, Y), {cx, cy, irx, iry} = FC;
  if (ice) {
    ell(P, cx, cy + 1, irx, iry, '#b9dcf2'); ell(P, cx, 17, 7, 2, '#b9dcf2');
    P(21, 18, 6, 20, C.stone); P(21, 18, 2, 20, C.stoneL); P(25, 18, 2, 20, C.stoneD);
    P(10, cy, 6, 1, '#ffffff'); P(31, cy + 4, 5, 1, '#ffffff');
    return;
  }
  /* ripples running outwards in the basin, flattened by the angle */
  for (let k = 0; k < 2; k++) {
    const f = (sec * .45 + k * .5) % 1, rr = 5 + f * 13;
    for (let i = 0; i < 22; i++) {
      const a = i / 22 * Math.PI * 2, px = Math.round(cx + Math.cos(a) * rr), py = Math.round(cy + 1 + Math.sin(a) * rr * iry / irx);
      if (Math.abs(px - cx) > 3 || py > cy + 2) P(px, py, 2, 1, '#6a98f4');
    }
  }
  /* jets from the top bowl falling into the basin */
  for (let i = 0; i < 12; i++) {
    const side = i % 2 ? 1 : -1, ph = (sec * 1.3 + i * .113) % 1, reach = 7 + (i % 3) * 3;
    const px = Math.round(cx + side * (5 + ph * reach)), py = Math.round(16 - Math.sin(ph * Math.PI) * 6 + ph * ph * 22);
    P(px, py, 1, 2, ph < .5 ? '#d8ecff' : '#9cc8f4');
  }
  P(23, 8 + Math.round(Math.sin(sec * 8)), 2, 9, '#d8ecff');
}
/* wooden sign on two posts */
function drawSign(g) {
  const P = painter(g, 0, 0);
  P(3, 9, 2, 9, C.trunk); P(11, 9, 2, 9, C.trunk);
  P(1, 2, 14, 8, '#a97c50'); P(1, 2, 14, 1, '#c99a66'); P(1, 9, 14, 1, '#6e4b2c'); P(14, 2, 1, 8, '#6e4b2c');
  P(3, 4, 10, 1, '#5e3b1f'); P(3, 6, 7, 1, '#5e3b1f');
}
function drawHouse(g, repaired, tx = 2, ty = 1) {
  const P = painter(g, tx * T, ty * T);
  const roof = repaired ? '#a8432f' : '#7a5a4a', roofD = repaired ? '#7e2f20' : '#5b4236';
  const wall = repaired ? '#c8945a' : '#9b7a58', wallD = repaired ? '#9e6e3c' : '#76593e';
  P(2, 20, 60, 28, wall);
  for (let x = 2; x < 62; x += 6) P(x, 20, 1, 28, wallD);
  P(2, 46, 60, 2, wallD);
  for (let r = 0; r < 20; r++) { const i = Math.floor((19 - r) / 3); P(i, r, 64 - 2 * i, 1, r % 4 === 3 ? roofD : roof); }
  P(6, 0, 52, 2, roofD);
  P(46, 1, 6, 9, '#7d7d74'); P(46, 1, 6, 1, '#9d9d92');
  const win = wx => {
    P(wx, 25, 12, 10, '#3b2a1f'); P(wx + 1, 26, 10, 8, repaired ? '#9fd3f0' : '#2f3b44');
    P(wx + 6, 26, 1, 8, '#3b2a1f'); P(wx + 1, 30, 10, 1, '#3b2a1f');
    if (repaired) { P(wx + 2, 27, 2, 2, '#d8f0fb'); P(wx - 1, 35, 14, 3, '#7e2f20'); P(wx, 34, 2, 1, '#e75480'); P(wx + 5, 34, 2, 1, '#f5d33b'); P(wx + 9, 34, 2, 1, '#e75480'); }
    else { P(wx - 1, 27, 14, 2, '#8a6a48'); P(wx - 1, 31, 14, 2, '#8a6a48'); }
  };
  win(8); win(44);
  P(35, 29, 10, 19, '#3b2a1f'); P(36, 30, 8, 18, repaired ? '#7a4a26' : '#5a3d26'); P(42, 39, 1, 1, C.coin || '#f0bf45');
  P(33, 46, 14, 2, '#8d8d84');
  if (!repaired) { P(14, 10, 5, 2, C.ink); P(40, 14, 5, 2, C.ink); P(22, 38, 3, 6, '#3b2a1f'); P(56, 24, 2, 8, '#3b2a1f'); }
}
function drawMarket(g, tx = 26, ty = 7) {
  const P = painter(g, tx * T, ty * T);
  P(2, 12, 76, 22, '#8b6a45');
  for (let x = 2; x < 78; x += 8) P(x, 12, 1, 22, '#6f5235');
  P(2, 10, 4, 38, C.fenceD); P(74, 10, 4, 38, C.fenceD);
  for (let i = 0; i < 10; i++) {
    const c = i % 2 ? '#f2e6bf' : '#c7432f';
    P(i * 8, 0, 8, 10, c); P(i * 8 + 1, 10, 6, 2, c); P(i * 8 + 2, 12, 4, 1, c);
  }
  P(0, 0, 80, 1, '#7e2a1d');
  const skin = '#f0c29a';
  P(34, 24, 12, 8, '#5b8fd6'); P(37, 25, 6, 7, '#f2e6bf');
  P(36, 16, 8, 8, skin); P(38, 19, 1, 1, C.ink); P(41, 19, 1, 1, C.ink); P(37, 21, 1, 1, '#e8907a'); P(42, 21, 1, 1, '#e8907a');
  P(35, 14, 10, 3, '#d6455a'); P(34, 16, 2, 4, '#d6455a'); P(44, 16, 2, 4, '#d6455a');
  P(0, 30, 80, 18, C.fence); P(0, 30, 80, 3, C.fenceL); P(0, 39, 80, 1, C.fenceD); P(0, 46, 80, 2, C.fenceD);
  P(6, 25, 18, 7, '#7a5230'); P(56, 25, 18, 7, '#7a5230');
  for (let i = 0; i < 5; i++) { P(8 + i * 3, 24, 2, 2, '#e8832a'); P(58 + i * 3, 24, 2, 2, i % 2 ? '#cf2f2f' : '#d63b45'); }
  P(28, 36, 24, 8, '#f2e6bf'); P(36, 38, 4, 4, '#f0bf45'); P(41, 38, 4, 4, '#f0bf45'); P(37, 39, 2, 2, '#c8922a'); P(42, 39, 2, 2, '#c8922a');
}


/* surfaces drawn every frame */
function drawSoil(g, X, Y, watered) {
  const P = painter(g, X, Y), s = watered ? C.soilW : C.soil, sd = watered ? C.soilWD : C.soilD;
  P(1, 1, 14, 14, s); P(2, 4, 12, 1, sd); P(2, 8, 12, 1, sd); P(2, 12, 12, 1, sd);
}
function drawWater(g, x, y, sec, edgeTop, ice) {
  const P = painter(g, x * T, y * T);
  if (ice) {
    P(0, 0, 16, 16, '#b9dcf2'); if (edgeTop) P(0, 0, 16, 2, '#97c4e6');
    line(P, Math.floor(hash(x, y, 1) * 10), 3, Math.floor(hash(x, y, 2) * 10) + 5, 12, 1, '#97c4e6');
    P(Math.floor(hash(x, y, 3) * 12), Math.floor(hash(x, y, 4) * 12), 3, 1, '#ffffff');
    return;
  }
  P(0, 0, 16, 16, C.water);
  if (edgeTop) P(0, 0, 16, 2, C.waterD);
  for (let i = 0; i < 3; i++) P(Math.floor((hash(x, y, i) * 16 + sec * 5 * (i % 2 ? 1 : -1) + 32) % 13), 3 + i * 5, 3, 1, C.waterL);
}

/* crops in the field */
function cropStage(c) {
  const d = CROPS[c.k];
  if (c.ripe) return 3;
  if (d.tree && c.grown) return 2;
  const p = c.age / d.grow;
  return p < 0.3 ? 0 : p < 0.6 ? 1 : 2;
}
function drawCrop(g, X, Y, k, st) {
  /* (X, Y) is the top-left of the crop's tile; tall plants grow above it and a little to the sides */
  const P = painter(g, X, Y), d = CROPS[k];
  if (k === 'apple') { drawAppleWood(g, X, Y, st); drawAppleLeaves(g, X, Y, st); if (st === 3) drawApples(g, X, Y); return; }
  if (st === 2 && k === 'peas') { P(3, -4, 1, 18, '#a07a4a'); P(12, -4, 1, 18, '#a07a4a'); P(3, -4, 10, 1, '#d9c9a0'); P(5, 2, 6, 8, C.leaf); P(4, -1, 3, 3, C.leafL); P(9, 0, 3, 3, C.leafL); return; }
  if (st === 2 && k === 'cucumber') { P(3, -2, 1, 16, '#a07a4a'); P(12, -2, 1, 16, '#a07a4a'); P(3, 1, 10, 1, '#d9c9a0'); P(4, 4, 8, 8, C.leaf); P(5, 2, 3, 3, C.leafL); P(9, 6, 3, 3, C.leafL); return; }
  if (st === 2 && k === 'corn') { P(7, -8, 2, 22, '#7ab83a'); P(3, -2, 4, 2, C.leaf); P(9, -5, 4, 2, C.leaf); P(2, 4, 5, 2, C.leaf); P(9, 2, 5, 2, C.leafL); return; }
  if (st === 0) { P(4, 9, 2, 2, '#4a2c16'); P(9, 8, 2, 2, '#4a2c16'); P(7, 11, 2, 1, '#4a2c16'); return; }
  if (st === 1) { P(7, 7, 2, 6, C.leaf); P(5, 6, 2, 2, C.leafL); P(9, 5, 2, 2, C.leafL); return; }
  if (st === 2) {
    if (k === 'pumpkin') { P(0, 10, 16, 2, C.leaf); P(1, 6, 4, 4, C.leafL); P(11, 6, 4, 4, C.leafL); P(7, 8, 2, 2, '#f5c84a'); return; }
    if (k === 'tomato') { P(7, -6, 2, 20, '#a07a4a'); P(4, -2, 8, 6, C.leaf); P(5, 4, 6, 6, C.leaf); P(3, 0, 3, 3, C.leafL); P(10, 3, 3, 3, C.leafL); return; }
    P(7, 3, 2, 10, C.leaf); P(4, 2, 3, 3, C.leafL); P(9, 0, 3, 3, C.leafL); P(3, 7, 3, 2, C.leaf); P(10, 6, 3, 2, C.leaf);
    return;
  }
  if (k === 'radish') {
    P(4, 2, 3, 6, C.leaf); P(9, 1, 3, 7, C.leaf); P(6, 0, 3, 8, C.leafL);
    P(5, 9, 6, 5, d.color); P(5, 9, 6, 1, '#f06a7a'); P(10, 10, 1, 4, '#a82438'); P(7, 14, 2, 1, '#f4e9e9');
  } else if (k === 'peas') {
    P(3, -6, 1, 20, '#a07a4a'); P(12, -6, 1, 20, '#a07a4a'); P(3, -6, 10, 1, '#d9c9a0'); P(3, 2, 10, 1, '#d9c9a0');
    P(4, -4, 8, 16, C.leaf); P(4, -3, 3, 3, C.leafL); P(9, 1, 3, 3, C.leafL); P(4, 10, 8, 2, C.leafD);
    [[5, -1], [9, 4], [6, 6], [10, -3]].forEach(([a, b]) => { P(a, b, 2, 4, d.color); P(a, b, 1, 4, '#b8ec8a'); });
    P(7, -5, 2, 2, '#ffffff'); P(10, 8, 2, 2, '#ffffff');
  } else if (k === 'cucumber') {
    P(3, -4, 1, 18, '#a07a4a'); P(12, -4, 1, 18, '#a07a4a'); P(3, -4, 10, 1, '#d9c9a0'); P(3, 3, 10, 1, '#d9c9a0');
    P(3, -2, 10, 14, C.leaf); P(4, -1, 3, 3, C.leafL); P(9, 3, 3, 3, C.leafL); P(3, 10, 10, 2, C.leafD);
    [[4, 2], [9, 6], [6, 8]].forEach(([a, b]) => { P(a, b, 2, 5, '#2e7d32'); P(a, b + 1, 1, 3, '#5aaa4a'); });
    P(8, -2, 2, 2, '#f5d33b'); P(5, 6, 2, 2, '#f5d33b');
  } else if (k === 'corn') {
    P(7, -20, 2, 34, '#7ab83a'); P(7, -20, 1, 34, '#5a9a2a');
    P(2, -8, 5, 2, C.leaf); P(9, -12, 5, 2, C.leaf); P(1, 0, 6, 2, C.leafL); P(9, -2, 6, 2, C.leaf); P(3, 6, 4, 2, C.leaf);
    P(9, -6, 3, 8, '#f2d14a'); P(9, -6, 1, 8, '#d9b02a'); P(9, -7, 3, 1, '#9ac85a'); P(8, 2, 1, 2, '#9ac85a');
    P(6, -24, 4, 4, '#d9c27a'); P(5, -22, 1, 2, '#d9c27a'); P(10, -22, 1, 2, '#d9c27a');
  } else if (k === 'carrot') {
    P(3, 1, 2, 6, C.leaf); P(5, -2, 2, 9, C.leaf); P(8, -4, 2, 11, C.leafL); P(10, -1, 2, 8, C.leaf); P(12, 2, 2, 5, C.leafL);
    P(5, 7, 6, 5, d.color); P(5, 7, 6, 1, '#f6a85a'); P(6, 12, 4, 2, '#d06a1c'); P(7, 14, 2, 1, '#d06a1c');
  } else if (k === 'potato') {
    P(2, 0, 12, 10, C.leaf); P(3, -2, 10, 2, C.leaf); P(4, -1, 4, 2, C.leafL); P(2, 8, 12, 2, C.leafD);
    P(5, -3, 2, 2, '#c9a6e8'); P(10, 0, 2, 2, '#f3f0ff'); P(7, 3, 2, 2, '#c9a6e8');
    P(1, 11, 4, 3, d.color); P(11, 11, 4, 3, d.color); P(6, 12, 3, 2, '#a87f4c');
  } else if (k === 'strawberry') {
    P(1, 7, 14, 6, C.leaf); P(3, 5, 4, 3, C.leafL); P(9, 5, 4, 3, C.leafL); P(1, 12, 14, 1, C.leafD);
    [[3, 10], [9, 9], [6, 12], [12, 11]].forEach(([a, b]) => { P(a, b, 3, 3, d.color); P(a + 1, b + 1, 1, 1, '#f5d33b'); });
  } else if (k === 'tomato') {
    P(7, -8, 2, 22, '#a07a4a');
    P(3, -5, 10, 8, C.leaf); P(2, 2, 12, 8, C.leaf); P(4, -7, 8, 2, C.leaf);
    P(3, -3, 3, 3, C.leafL); P(10, 4, 3, 3, C.leafL); P(2, 9, 12, 2, C.leafD);
    [[4, -2], [9, 1], [3, 5], [10, 7], [6, 9]].forEach(([a, b]) => { P(a, b, 3, 3, d.color); P(a, b, 1, 1, '#ff8a70'); });
  } else if (k === 'pumpkin') {
    P(0, 12, 16, 2, C.leaf); P(0, 5, 4, 4, C.leafL); P(12, 4, 4, 3, C.leafL);
    P(2, 5, 12, 9, d.color); P(1, 7, 14, 6, d.color); P(3, 5, 4, 1, '#f5a94a');
    P(5, 6, 1, 7, '#c46d10'); P(8, 5, 1, 9, '#c46d10'); P(11, 6, 1, 7, '#c46d10'); P(7, 2, 2, 4, '#5a7a2a'); P(2, 13, 12, 1, '#b85f0c');
  }
}

/* apple tree in parts, so the leaves can change with the seasons */
function drawAppleWood(g, X, Y, st) {
  const P = painter(g, X, Y);
  if (st === 0) { P(7, 6, 2, 10, C.trunk); return; }
  if (st === 1) { P(7, 2, 2, 14, C.trunk); P(7, 2, 1, 14, C.trunkD); line(P, 8, 4, 3, -5, 1, C.trunk); line(P, 8, 2, 13, -6, 1, C.trunk); line(P, 8, 0, 8, -9, 1, C.trunk); return; }
  line(P, 7, 2, -3, -16, 2, C.trunk); line(P, 8, 0, 18, -16, 2, C.trunk); line(P, 8, -1, 8, -24, 2, C.trunk);
  line(P, 3, -7, -5, -10, 1, C.trunk); line(P, 13, -8, 21, -11, 1, C.trunk); line(P, 8, -14, 2, -22, 1, C.trunk); line(P, 9, -14, 14, -22, 1, C.trunk);
  P(6, -2, 4, 18, C.trunk); P(6, -2, 1, 18, C.trunkD); P(4, 14, 8, 2, C.trunk);
}
function drawAppleLeaves(g, X, Y, st) {
  const P = painter(g, X, Y);
  if (st === 0) { P(5, 5, 3, 2, C.leafL); P(9, 3, 3, 2, C.leafL); P(8, 8, 3, 1, C.leaf); return; }
  if (st === 1) {
    P(2, -8, 12, 11, C.leaf); P(1, -5, 14, 6, C.leaf); P(4, -10, 8, 2, C.leaf);
    P(4, -8, 4, 2, C.leafL); P(2, -4, 3, 2, C.leafL); P(2, 1, 12, 2, C.leafD); P(12, -6, 2, 6, C.leafD);
    return;
  }
  P(-4, -22, 24, 18, C.leaf); P(-6, -18, 28, 11, C.leaf); P(0, -25, 16, 3, C.leaf); P(-2, -5, 20, 3, C.leaf);
  P(-6, -9, 28, 2, C.leafD); P(14, -20, 6, 12, C.leafD); P(0, -3, 16, 1, C.leafD);
  P(0, -23, 8, 3, C.leafL); P(-4, -18, 5, 4, C.leafL); P(5, -19, 3, 2, C.leafL);
}
function drawApples(g, X, Y) {
  const P = painter(g, X, Y);
  [[-2, -14], [5, -20], [12, -12], [2, -8], [9, -16], [15, -7], [-4, -8]].forEach(([a, b]) => { P(a, b, 3, 3, CROPS.apple.color); P(a, b, 1, 1, '#f07070'); });
}
/* a plant that withered because its season ended */
function drawDead(g, X, Y) {
  const P = painter(g, X, Y);
  P(5, 5, 1, 9, '#7a5a2a'); P(8, 3, 1, 11, '#8a6a3a'); P(11, 6, 1, 8, '#6a4a20');
  P(3, 6, 2, 1, '#9a7a3a'); P(9, 4, 3, 1, '#9a7a3a'); P(12, 8, 2, 1, '#9a7a3a'); P(6, 9, 2, 1, '#8a6a3a'); P(4, 13, 9, 1, '#5a3a18');
}

/* icons */
function drawProduce(g, k, ox = 2, oy = 2) {
  const P = painter(g, ox, oy), c = CROPS[k].color;
  if (k === 'radish') { P(4, 0, 2, 3, C.leafL); P(7, 0, 2, 3, C.leaf); P(3, 3, 7, 6, c); P(2, 4, 9, 4, c); P(4, 9, 5, 1, c); P(6, 10, 1, 2, '#f4e9e9'); P(4, 4, 2, 2, '#f06a7a'); }
  else if (k === 'peas') { P(1, 4, 11, 5, c); P(0, 5, 13, 3, c); P(1, 4, 11, 1, '#5aa83a'); [2, 5, 8].forEach(a => P(a, 5, 2, 2, '#c8f09a')); P(11, 2, 2, 2, C.leaf); }
  else if (k === 'cucumber') { P(2, 3, 9, 4, c); P(1, 4, 11, 3, c); P(3, 7, 7, 2, c); P(3, 4, 7, 1, '#5aaa4a'); P(4, 6, 1, 1, '#a8d88a'); P(8, 5, 1, 1, '#a8d88a'); P(11, 3, 2, 2, '#f5d33b'); }
  else if (k === 'corn') { P(4, 0, 5, 12, c); P(3, 2, 7, 8, c); [1, 4, 7].forEach(b => P(4, b + 1, 5, 1, '#d9b02a')); P(1, 6, 3, 6, '#7ab83a'); P(9, 5, 3, 7, '#7ab83a'); }
  else if (k === 'carrot') { P(8, 0, 2, 3, C.leafL); P(10, 1, 2, 2, C.leaf); P(6, 3, 4, 3, c); P(4, 5, 4, 3, c); P(3, 7, 3, 2, c); P(2, 9, 2, 2, c); P(1, 11, 1, 1, c); P(7, 3, 1, 1, '#f6a85a'); }
  else if (k === 'potato') { P(2, 3, 9, 7, c); P(1, 4, 11, 5, c); P(3, 2, 6, 1, c); P(2, 8, 9, 2, '#a87f4c'); P(4, 5, 1, 1, '#8a6438'); P(8, 6, 1, 1, '#8a6438'); P(6, 3, 1, 1, '#8a6438'); }
  else if (k === 'strawberry') { P(4, 0, 5, 2, C.leafL); P(2, 2, 9, 4, c); P(3, 6, 7, 3, c); P(5, 9, 3, 2, c); P(4, 3, 1, 1, '#f5d33b'); P(8, 4, 1, 1, '#f5d33b'); P(6, 6, 1, 1, '#f5d33b'); }
  else if (k === 'tomato') { P(2, 3, 9, 8, c); P(1, 5, 11, 4, c); P(3, 2, 7, 1, c); P(5, 1, 3, 2, C.leaf); P(3, 4, 2, 2, '#ff8a70'); }
  else if (k === 'pumpkin') { P(1, 4, 11, 7, c); P(2, 3, 9, 9, c); P(4, 4, 1, 7, '#c46d10'); P(8, 4, 1, 7, '#c46d10'); P(5, 1, 2, 3, '#5a7a2a'); }
  else if (k === 'apple') { P(2, 3, 9, 8, c); P(1, 5, 11, 5, c); P(3, 11, 7, 1, c); P(6, 0, 1, 3, C.trunk); P(7, 1, 3, 2, C.leafL); P(3, 5, 2, 2, '#f07070'); }
}
function iconCanvas(kind, k) {
  const c = document.createElement('canvas'); c.width = 16; c.height = 16;
  const g = c.getContext('2d'), P = painter(g, 0, 0);
  if (kind === 'hoe') {
    /* hoe: a long thin handle leaning the other way, a flat blade bent down at its tip */
    for (let i = 0; i < 12; i++) P(13 - i, 15 - i, 1, 1, C.trunk);
    for (let i = 0; i < 11; i++) P(13 - i, 14 - i, 1, 1, '#a97c50');
    P(0, 3, 5, 2, '#6f777f'); P(0, 5, 5, 3, '#9aa3ad'); P(0, 7, 5, 1, '#c9d0d6');
  } else if (kind === 'axe') {
    /* axe: a short thick handle and a broad wedge head with a curved edge */
    for (let i = 0; i < 9; i++) P(4 + i, 15 - i, 2, 2, C.trunk);
    P(9, 2, 3, 7, '#6f777f'); P(12, 1, 2, 9, '#9aa3ad'); P(14, 2, 2, 7, '#c9d0d6'); P(12, 0, 2, 1, '#9aa3ad'); P(12, 10, 2, 1, '#9aa3ad');
    P(9, 2, 3, 1, '#9aa3ad');
  } else if (kind === 'pick') {
    /* double pickaxe: a straight handle and a head pointing both ways */
    P(7, 4, 2, 12, C.trunk); P(7, 4, 1, 12, C.trunkD);
    P(3, 2, 10, 3, '#9aa3ad'); P(3, 2, 10, 1, '#c9d0d6'); P(3, 4, 10, 1, '#6f777f');
    P(1, 3, 3, 2, '#9aa3ad'); P(0, 5, 2, 2, '#9aa3ad'); P(0, 7, 1, 1, '#6f777f');
    P(12, 3, 3, 2, '#9aa3ad'); P(14, 5, 2, 2, '#9aa3ad'); P(15, 7, 1, 1, '#6f777f');
    P(6, 1, 4, 5, '#6f777f'); P(6, 1, 4, 1, '#9aa3ad');
  } else if (kind === 'scythe') {
    for (let i = 0; i < 12; i++) P(4 + Math.floor(i * .6), 15 - i, 2, 1, C.trunk);
    P(3, 2, 9, 2, '#c9d0d6'); P(1, 3, 3, 2, '#c9d0d6'); P(0, 5, 2, 2, '#9aa3ad'); P(11, 3, 3, 1, '#9aa3ad');
  } else if (kind === 'wood') {
    P(1, 6, 13, 4, C.trunk); P(1, 6, 13, 1, '#a97c50'); P(12, 6, 3, 4, '#c99a66'); P(13, 7, 1, 2, C.trunkD);
    P(2, 10, 12, 4, C.trunkD); P(2, 10, 12, 1, C.trunk); P(11, 10, 3, 4, '#c99a66'); P(12, 11, 1, 2, C.trunk);
  } else if (kind === 'stone') {
    P(2, 7, 8, 6, C.stone); P(3, 6, 6, 1, C.stoneL); P(2, 12, 8, 1, C.stoneD); P(8, 5, 6, 6, C.stoneD); P(9, 4, 4, 2, C.stone); P(9, 4, 2, 1, C.stoneL);
  } else if (kind.startsWith('eq-')) {
    const c = 'rgba(170,180,232,.45)';
    if (kind === 'eq-head') { P(5, 3, 6, 3, c); P(2, 6, 12, 2, c); }
    if (kind === 'eq-body') { P(4, 3, 8, 10, c); P(2, 4, 2, 6, c); P(12, 4, 2, 6, c); }
    if (kind === 'eq-legs') { P(4, 2, 8, 4, c); P(4, 6, 3, 8, c); P(9, 6, 3, 8, c); }
    if (kind === 'eq-feet') { P(2, 8, 5, 5, c); P(9, 8, 5, 5, c); P(1, 12, 6, 2, c); P(9, 12, 6, 2, c); }
  } else if (kind === 'can') {
    P(3, 6, 9, 8, '#7d9bb5'); P(3, 6, 9, 2, '#a9c2d6'); P(12, 8, 2, 2, '#7d9bb5'); P(14, 6, 2, 3, '#7d9bb5');
    P(5, 3, 5, 1, '#5e7a92'); P(4, 3, 1, 3, '#5e7a92'); P(10, 3, 1, 3, '#5e7a92');
  } else if (kind === 'seed') {
    P(2, 1, 12, 14, '#efe0b4'); P(2, 1, 12, 2, CROPS[k].color); P(2, 14, 12, 1, '#c9b48a');
    drawProduce(g, k, 3, 3);
  } else if (kind === 'prod') drawProduce(g, k);
  else if (kind === 'field') {
    P(1, 6, 14, 9, C.soil); P(2, 8, 12, 1, C.soilD); P(2, 11, 12, 1, C.soilD); P(7, 2, 2, 5, C.leaf); P(5, 2, 2, 2, C.leafL); P(9, 1, 2, 2, C.leafL);
  } else if (kind === 'house') {
    for (let r = 0; r < 6; r++) P(7 - r, 2 + r, 2 + r * 2, 1, '#a8432f');
    P(3, 8, 10, 7, '#c8945a'); P(7, 11, 3, 4, '#7a4a26'); P(4, 10, 2, 2, '#9fd3f0');
  }
  return c;
}


/* player: 16 x 24, feet on the bottom row */
function drawPlayer(g, X, Y, face, frame) {
  const P = painter(g, X, Y);
  const skin = '#f2c39b', skinD = '#d9a27a', hat = '#e3c069', hatD = '#b8953f', band = '#9c6b2f';
  const shirt = '#c0563a', shirtD = '#963f29', over = '#3d5a8c', overD = '#2b4168', boot = '#4a2f1d', hair = '#7a4a22';
  const side = face === 'left' || face === 'right', step = frame ? 1 : 0;
  /* legs and boots */
  if (side) {
    P(6, 18, 4, 4, over); P(6, 18, 1, 4, overD);
    if (step) { P(4, 19, 3, 3, over); P(9, 19, 3, 3, overD); P(3, 22, 4, 2, boot); P(9, 22, 4, 2, boot); }
    else P(5, 22, 6, 2, boot);
  } else {
    P(5, 18, 2, 4 - step, over); P(9, 18, 2, 4, over); P(9, 18, 1, 4, overD);
    P(5, 22 - step, 2, 2, boot); P(9, 22, 2, 2, boot);
  }
  /* body */
  P(4, 12, 8, 6, shirt); P(11, 12, 1, 6, shirtD); P(5, 13, 6, 5, over); P(5, 17, 6, 1, overD);
  if (!side) { P(5, 12, 1, 1, over); P(10, 12, 1, 1, over); P(6, 15, 1, 1, '#f0bf45'); P(9, 15, 1, 1, '#f0bf45'); }
  /* arms */
  if (side) { const ax = face === 'left' ? 6 : 8; P(ax, 13, 2, 4, shirtD); P(ax, 17, 2, 1, skin); }
  else { P(3, 12 + step, 1, 5, shirt); P(12, 12 - step + 1, 1, 4, shirtD); P(3, 17 + step, 1, 1, skin); P(12, 17, 1, 1, skin); }
  /* head */
  P(4, 5, 8, 7, skin); P(5, 11, 6, 1, skin);
  if (face === 'up') { P(4, 5, 8, 6, hair); P(5, 11, 6, 1, skinD); }
  else if (face === 'down') {
    P(11, 6, 1, 5, skinD); P(4, 5, 1, 3, hair); P(11, 5, 1, 3, hair); P(5, 5, 6, 1, hair);
    P(6, 8, 1, 2, C.ink); P(9, 8, 1, 2, C.ink); P(7, 10, 2, 1, '#b5655a'); P(5, 9, 1, 1, '#eaa48a'); P(10, 9, 1, 1, '#eaa48a');
  } else if (face === 'left') {
    P(8, 5, 4, 5, hair); P(3, 8, 1, 2, skin); P(5, 8, 1, 2, C.ink); P(5, 10, 2, 1, '#b5655a'); P(9, 8, 1, 2, skinD);
  } else {
    P(4, 5, 4, 5, hair); P(12, 8, 1, 2, skin); P(10, 8, 1, 2, C.ink); P(9, 10, 2, 1, '#b5655a'); P(6, 8, 1, 2, skinD);
  }
  /* straw hat */
  P(6, 0, 4, 1, hat); P(5, 1, 6, 2, hat); P(5, 3, 6, 1, band); P(2, 4, 12, 2, hat); P(2, 5, 12, 1, hatD);
}

/* ---------- seasons ---------- */
const SEASONS = [{id:'spring', name:'Весна'}, {id:'summer', name:'Лето'}, {id:'autumn', name:'Осень'}, {id:'winter', name:'Зима'}];
const SEASON_DAYS = 12;
function seasonOf(day) { const i = Math.floor((day - 1) / SEASON_DAYS) % 4; return {i, id:SEASONS[i].id, name:SEASONS[i].name, d:(day - 1) % SEASON_DAYS + 1}; }
const rgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
const toHex = a => '#' + a.map(v => Math.round(v).toString(16).padStart(2, '0')).join('');
const mix = (a, b, t) => { const A = rgb(a), B = rgb(b); return toHex(A.map((v, i) => v + (B[i] - v) * t)); };
const mixPal = (a, b, t) => a.map((c, i) => mix(c, b[i], Math.max(0, Math.min(1, t))));
/* grass: [base, dark, light]; leaves: [base, light, dark] in the order of C.leaf, C.leafL, C.leafD */
const GRASS = {spring:['#3fb83a', '#2a922e', '#7ee05a'], summer:[C.grass, C.grassD, C.grassL], autumn:['#a3a63a', '#7e8a2c', '#c9c25a'], winter:['#6f8f5c', '#587a4a', '#8fa874']};
const LEAVES = {spring:['#5fd35a', '#9be87a', '#2f9e3a'], summer:[C.leaf, C.leafL, C.leafD],
  autumnA:['#b5b52a', '#dcd84a', '#7a7e1a'], autumnB:['#e0a02a', '#f5d04a', '#a8601a'], autumnC:['#d9662a', '#f09a40', '#963c18']};
/* How the world looks on a given day: leaf cover and colour, blossom, fallen leaves, flowers, grass, snow and ice */
function lookFor(day, snow) {
  const s = seasonOf(day), t = (s.d - 1) / (SEASON_DAYS - 1);
  const L = {season:s.id, d:s.d, snow:!!snow, ice:s.id === 'winter', cov:1, leaves:LEAVES.summer, blossom:0, fallen:0, flowers:'some', grass:GRASS.summer};
  if (s.id === 'spring') {
    L.cov = t; L.leaves = LEAVES.spring; L.blossom = Math.max(0, 1 - Math.abs(t - .5) * 2.2); L.flowers = 'bloom';
    L.grass = mixPal(GRASS.winter, GRASS.spring, t * 3);
  } else if (s.id === 'autumn') {
    L.leaves = t < .33 ? mixPal(LEAVES.summer, LEAVES.autumnA, t / .33) : t < .66 ? mixPal(LEAVES.autumnA, LEAVES.autumnB, (t - .33) / .33) : mixPal(LEAVES.autumnB, LEAVES.autumnC, (t - .66) / .34);
    L.cov = t < .6 ? 1 : Math.max(0, 1 - (t - .6) / .4);
    L.fallen = Math.max(0, t - .4) / .6; L.flowers = 'wither'; L.grass = mixPal(GRASS.summer, GRASS.autumn, t);
  } else if (s.id === 'winter') { L.cov = 0; L.flowers = 'none'; L.grass = GRASS.winter; L.fallen = .3; }
  L.key = s.id + s.d + (L.snow ? 's' : '');
  return L;
}
const SUMMER = lookFor(SEASON_DAYS + 1, false);
/* recolour leaf pixels to the season and drop the ones that have fallen; small clumps fall together */
const LEAF_RGB = [C.leaf, C.leafL, C.leafD].map(rgb);
function seasonLeaves(c, look, seed, blossom = 1) {
  const g = c.getContext('2d'), im = g.getImageData(0, 0, c.width, c.height), d = im.data;
  const pal = look.leaves.map(rgb), bl = [[255, 255, 255], [255, 190, 215]];
  for (let y = 0; y < c.height; y++) for (let x = 0; x < c.width; x++) {
    const i = (y * c.width + x) * 4;
    if (!d[i + 3]) continue;
    const k = LEAF_RGB.findIndex(L => L[0] === d[i] && L[1] === d[i + 1] && L[2] === d[i + 2]);
    if (k < 0) continue;
    if (hash(x >> 1, y >> 1, seed) >= look.cov) { d[i + 3] = 0; continue; }
    let col = pal[k];
    if (look.blossom && hash(x, y, seed + 7) < look.blossom * .14 * blossom) col = bl[hash(x, y, seed + 9) < .5 ? 0 : 1];
    d[i] = col[0]; d[i + 1] = col[1]; d[i + 2] = col[2];
  }
  g.putImageData(im, 0, 0);
}
/* a cap of snow on every surface that faces up */
function snowCap(c) {
  const g = c.getContext('2d'), w = c.width, h = c.height, im = g.getImageData(0, 0, w, h), d = im.data;
  const a = new Uint8Array(w * h);
  for (let i = 0; i < w * h; i++) a[i] = d[i * 4 + 3] > 0 ? 1 : 0;
  const put = (x, y, col) => { const i = (y * w + x) * 4; d[i] = col[0]; d[i + 1] = col[1]; d[i + 2] = col[2]; d[i + 3] = 255; };
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (!a[y * w + x] || (y > 0 && a[(y - 1) * w + x])) continue;
    put(x, y, [246, 250, 255]);
    if (y + 2 < h && a[(y + 1) * w + x] && a[(y + 2) * w + x]) put(x, y + 1, [220, 230, 244]);
  }
  g.putImageData(im, 0, 0);
}
function layer(w, h, fn) { const c = document.createElement('canvas'); c.width = w; c.height = h; const g = c.getContext('2d'); g.imageSmoothingEnabled = false; fn(g); return c; }

/* ---------- objects: sprites that stand on the ground and can be taller or wider than a tile ---------- */
/* Each object sprite is a canvas plus its anchor (ax, ay): the point that touches the ground.
   Objects are drawn sorted by that point, so the one in front covers the one behind. */
const cache = new Map();
function cached(key, w, h, ax, ay, fn) {
  let o = cache.get(key);
  if (!o) {
    const c = document.createElement('canvas'); c.width = w; c.height = h;
    const g = c.getContext('2d'); g.imageSmoothingEnabled = false; fn(g);
    /* fy: the lowest painted row. The shadow starts there, so it always touches the object's base */
    let fy = h;
    try {
      const px = g.getImageData(0, 0, w, h).data;
      fy = 0;
      for (let y = h - 1; y >= 0 && !fy; y--) for (let x = 0; x < w; x++) if (px[(y * w + x) * 4 + 3] > 0) { fy = y + 1; break; }
      if (!fy) fy = h;
    } catch (e) {}
    o = {img:c, ax, ay, w, h, fy}; cache.set(key, o);
  }
  return o;
}
/* look: the day's lookFor(); summer by default. Snow caps and season colours are baked into the cached canvas */
function sprite(kind, a, b, look = SUMMER) {
  const o = spriteRaw(kind, a, b, look), bx = BOXES[kind];
  if (o && bx && !o.shadow) { const boxes = Array.isArray(bx) ? bx : bx[a]; if (boxes) o.shadow = (g, o2, px, py, sun) => boxShadow(g, px - o2.ax, py - o2.ay, boxes, sun); }
  return o;
}
function spriteRaw(kind, a, b, look) {
  const lk = look.key, sn = g => { if (look.snow) snowCap(g.canvas); };
  switch (kind) {
    case 'tree':   return cached('tree' + a + lk, 32, 40, 16, 40, g => {
      drawTreeWood(g, a);
      const leaves = layer(32, 40, lg => drawTreeCanopy(lg, a)); seasonLeaves(leaves, look, 31 + a, .6); g.drawImage(leaves, 0, 0); sn(g);
    });
    case 'bush':   return cached('bush' + lk, 20, 16, 10, 16, g => {
      drawBushTwigs(g);
      const leaves = layer(20, 16, drawBushLeaves); seasonLeaves(leaves, look, 41); g.drawImage(leaves, 0, 0);
      if (look.season === 'summer') drawBerries(g);
      sn(g);
    });
    case 'well':   return cached('well' + lk, 16, 28, 8, 28, g => { drawWell(g); sn(g); });
    case 'house':  return cached('house' + (a ? 1 : 0) + lk, 64, 60, 0, 60, g => {
      const P = painter(g, 0, 0);
      P(46, 0, 7, 16, '#7d7d74'); P(46, 0, 7, 2, '#9d9d92'); P(51, 2, 2, 14, '#626259');
      drawHouse(g, a, 0, 12 / T); sn(g);
    });
    case 'bin':     return cached('bin' + (look.snow ? 's' : ''), 16, 16, 8, 16, g => { drawBin(g); sn(g); });
    case 'mailbox': return cached('mailbox' + (look.snow ? 's' : ''), 12, 22, 6, 22, g => { drawMailbox(g); sn(g); });
    case 'rock':    return cached('rock' + (look.snow ? 's' : ''), 16, 12, 8, 12, g => { drawRock(g); sn(g); });
    case 'twigs':   return cached('twigs' + (look.snow ? 's' : ''), 16, 8, 8, 8, g => { drawTwigs(g); sn(g); });
    case 'stump':   return cached('stump' + (look.snow ? 's' : ''), 16, 10, 8, 10, g => { drawStump(g); sn(g); });
    case 'bigtree': return cached('bigtree' + lk, 48, 64, 24, 64, g => {
      drawBigTree(g, look);
      const leaves = layer(48, 64, drawBigCanopy); seasonLeaves(leaves, look, 61, .5); g.drawImage(leaves, 0, 0); sn(g);
    });
    case 'barrier': return a === 'h' ? cached('barrierh' + (look.snow ? 's' : ''), 32, 18, 16, 18, g => { drawBarrier(g, 'h'); sn(g); })
                                     : cached('barrierv' + (look.snow ? 's' : ''), 14, 36, 7, 36, g => { drawBarrier(g, 'v'); sn(g); });
    case 'signpost':  return cached('signpost' + (look.snow ? 's' : ''), 18, 26, 9, 26, g => { drawSignpost(g); sn(g); });
    case 'scarecrow': return cached('scarecrow' + (look.snow ? 's' : ''), 16, 28, 8, 28, g => { drawScarecrow(g); sn(g); });
    case 'sunflower': return cached('sunflower' + a, 14, 26, 7, 26, g => drawSunflower(g, a));
    case 'haystack':  return cached('haystack' + (look.snow ? 's' : ''), 24, 18, 12, 18, g => { drawHaystack(g); sn(g); });
    case 'stall':     return cached('stall' + a + b + (look.snow ? 's' : ''), 64, 48, 0, 48, g => { drawStall(g, a, b); sn(g); });
    case 'stallside': return cached('stallside' + a + b + (look.snow ? 's' : ''), 48, 64, 0, 64, g => { drawStallSide(g, a, b); sn(g); });
    case 'stallback': return cached('stallback' + (look.snow ? 's' : ''), 64, 40, 0, 40, g => { drawStallBack(g); sn(g); });
    case 'tent': { const o = cached('tent' + b + (look.snow ? 's' : ''), 64, 64, 0, 64, g => { drawTent(g, b); sn(g); }); o.shadow = tentShadow; return o; }
    case 'fountain': {
      /* the basin stands on the ground, so its shadow starts at the widest line of the oval, not at the front wall */
      const o = cached('fountain' + (look.snow ? 's' : ''), 48, 56, 0, 56, g => { drawFountain(g); sn(g); });
      o.fy = FC.cy; o.shadow = fountainShadow; return o;
    }
    case 'stake':   return cached('stake' + (look.snow ? 's' : ''), 8, 14, 3, 14, g => { drawStake(g); sn(g); });
    case 'sign':    return cached('sign' + (look.snow ? 's' : ''), 16, 18, 8, 18, g => { drawSign(g); sn(g); });
    case 'market': return cached('market' + lk, 80, 48, 0, 48, g => { drawMarket(g, 0, 0); sn(g); });
    case 'player': return cached('player' + a + b, 16, 24, 8, 24, g => drawPlayer(g, 0, 0, a, b));
    case 'crop':
      if (a === 'apple') return cached('crop' + a + b + lk, 32, 44, 16, 44, g => {
        drawAppleWood(g, 8, 28, b);
        const leaves = layer(32, 44, lg => drawAppleLeaves(lg, 8, 28, b)); seasonLeaves(leaves, look, 51); g.drawImage(leaves, 0, 0);
        if (b === 3) drawApples(g, 8, 28);
        sn(g);
      });
      return cached('crop' + a + b + (look.snow ? 's' : ''), 32, 44, 16, 44, g => { drawCrop(g, 8, 28, a, b); sn(g); });
    case 'dead':   return cached('dead' + (look.snow ? 's' : ''), 16, 16, 8, 16, g => { drawDead(g, 0, 0); sn(g); });
    case 'fence':  return cached('fence' + a + (look.snow ? 's' : ''), 16, 16, 8, 16, g => { drawFencePiece(g, 0, 0, a); sn(g); });
    case 'deco':   return cached('deco' + a + look.season + (look.snow ? 's' : ''), 16, 16, 8, 16, g => { drawDeco(g, 0, 0, a, look.season); sn(g); });
    case 'flower': return cached('flower' + a + ',' + b + look.flowers, 16, 16, 8, 16, g => drawFlowerDots(g, 0, 0, a, b, look.flowers));
  }
  return null;
}
/* the cache keeps one day's looks; the game empties it every morning */
function clearCache() { cache.clear(); }
const sils = new WeakMap();
function silhouette(img) {
  let s = sils.get(img);
  if (!s) {
    s = document.createElement('canvas'); s.width = img.width; s.height = img.height;
    const g = s.getContext('2d'); g.drawImage(img, 0, 0);
    g.globalCompositeOperation = 'source-in'; g.fillStyle = '#06102a'; g.fillRect(0, 0, s.width, s.height);
    sils.set(img, s);
  }
  return s;
}

/* ---------- sun and light ---------- */
/* The sun rises at 6:00 in the east and sets at 20:30 in the west.
   Shadows fall away from it: long and to the left in the morning, short at noon, long and to the right in the evening. */
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
function sunAt(min) {
  const t = (min - 360) / 870;
  if (t <= 0 || t >= 1) return null;
  const a = t * Math.PI, elev = Math.sin(a);
  return {
    shear: -Math.cos(a) * clamp(0.35 / Math.max(elev, 0.2), 0.35, 1.4),
    len: clamp(0.22 + (1 - elev) * 0.45, 0.22, 0.65),
    alpha: 0.34 * Math.min(1, elev * 3.5)
  };
}
/* g must already carry the world transform; (px, py) is where the object touches the ground */
/* a low wide basin: its shadow is the oval itself, pushed away from the sun by the height of the wall,
   plus a strip from the pedestal and the top bowl */
function fountainShadow(g, o, px, py, sun) {
  const X = px - o.ax, Y = py - o.ay, {cx, cy, rx, ry, wall} = FC;
  g.fillStyle = '#06102a';
  const dx = sun.shear * wall * 1.6, dy = sun.len * wall * 1.6;
  for (let y = -ry; y <= ry; y++) { const w = Math.round(rx * Math.sqrt(1 - (y / ry) ** 2)); g.fillRect(Math.round(X + cx - w + dx), Math.round(Y + cy + y + dy), w * 2, 1); }
  for (let i = 0; i <= 22; i++) {
    const w = i > 17 ? 9 : 3;
    g.fillRect(Math.round(X + cx - w + sun.shear * i), Math.round(Y + cy + sun.len * i), w * 2, 1);
  }
}
/* shadow of a solid with a footprint on the ground: every horizontal slice of it, from the ground up,
   is laid on the ground shifted away from the sun by its height. Walls keep the footprint up to wallH,
   then the roof narrows to its ridge (ridge: 0 for a point, or a width) by peakH */
function volumeShadow(g, X, Y, f, wallH, peakH, ridge, sun) {
  g.fillStyle = '#06102a';
  const cx = (f.x0 + f.x1) / 2, cy = (f.y0 + f.y1) / 2, hw = (f.x1 - f.x0) / 2, hd = (f.y1 - f.y0) / 2;
  for (let h = 0; h <= peakH; h++) {
    const k = h <= wallH ? 1 : 1 - (h - wallH) / (peakH - wallH);
    const w = Math.max(ridge / 2, hw * k), d = hd * k;
    g.fillRect(Math.round(X + cx - w + sun.shear * h), Math.round(Y + cy - d + sun.len * h), Math.max(1, Math.round(w * 2)), Math.max(1, Math.round(d * 2)));
  }
}
/* Objects with depth or lying on the ground are described as simple boxes for their shadow:
   a footprint on the ground (x0..x1, y0..y1 in the sprite), heights h0..h1, and a top shape:
   'point' narrows to a point (rock, haystack), 'ridge' narrows only in depth (a gable roof). */
const BOXES = {
  house:     [{x0:2, x1:62, y0:36, y1:60, h0:0, h1:28}, {x0:2, x1:62, y0:36, y1:60, h0:28, h1:44, top:'ridge'}, {x0:46, x1:53, y0:42, y1:46, h0:0, h1:52}],
  well:      [{x0:1, x1:15, y0:20, y1:28, h0:0, h1:6}, {x0:2, x1:4, y0:22, y1:24, h0:0, h1:23}, {x0:12, x1:14, y0:22, y1:24, h0:0, h1:23}, {x0:0, x1:16, y0:19, y1:26, h0:22, h1:26}],
  stall:     [{x0:2, x1:62, y0:26, y1:30, h0:0, h1:28}, {x0:0, x1:64, y0:26, y1:44, h0:28, h1:31}, {x0:0, x1:64, y0:40, y1:48, h0:0, h1:12}],
  stallside: [{x0:0, x1:5, y0:20, y1:62, h0:0, h1:26}, {x0:0, x1:20, y0:20, y1:62, h0:26, h1:29}, {x0:32, x1:46, y0:28, y1:62, h0:0, h1:12}],
  stallback: [{x0:2, x1:62, y0:34, y1:40, h0:0, h1:24}, {x0:0, x1:64, y0:20, y1:40, h0:24, h1:27}],
  bin:       [{x0:1, x1:15, y0:9, y1:16, h0:0, h1:7}],
  rock:      [{x0:2, x1:14, y0:6, y1:12, h0:0, h1:7, top:'point'}],
  stump:     [{x0:3, x1:13, y0:6, y1:10, h0:0, h1:5}],
  twigs:     [{x0:1, x1:15, y0:1, y1:8, h0:0, h1:1}],
  haystack:  [{x0:2, x1:22, y0:9, y1:18, h0:0, h1:14, top:'point'}],
  barrier:   {h:[{x0:1, x1:4, y0:15, y1:18, h0:0, h1:14}, {x0:28, x1:31, y0:15, y1:18, h0:0, h1:10}, {x0:2, x1:31, y0:15, y1:18, h0:9, h1:11}],
              v:[{x0:5, x1:9, y0:2, y1:5, h0:0, h1:10}, {x0:5, x1:9, y0:32, y1:36, h0:0, h1:10}, {x0:5, x1:8, y0:3, y1:34, h0:8, h1:10}]}
};
function boxShadow(g, X, Y, boxes, sun) {
  g.fillStyle = '#06102a';
  boxes.forEach(b => {
    const cx = (b.x0 + b.x1) / 2, cy = (b.y0 + b.y1) / 2, hw = (b.x1 - b.x0) / 2, hd = (b.y1 - b.y0) / 2;
    for (let h = b.h0; h <= b.h1; h++) {
      const k = b.top ? 1 - (h - b.h0) / Math.max(1, b.h1 - b.h0) : 1;
      const w = b.top === 'point' ? hw * k : hw, d = hd * k;
      g.fillRect(Math.round(X + cx - w + sun.shear * h), Math.round(Y + cy - d + sun.len * h), Math.max(1, Math.round(w * 2)), Math.max(1, Math.round(d * 2)));
    }
  });
}
function tentShadow(g, o, px, py, sun) {
  volumeShadow(g, px - o.ax, py - o.ay, {x0:4, x1:60, y0:38, y1:62}, 22, 50, 2, sun);
}
function castShadow(g, o, px, py, sun) {
  if (o.shadow) return o.shadow(g, o, px, py, sun);
  const foot = py - o.ay + o.fy;
  g.save();
  g.transform(1, 0, -sun.shear, -sun.len, px - o.ax + sun.shear * o.fy, foot + sun.len * o.fy);
  /* only what rises above the ground line casts a shadow */
  if (o.fy > 0) g.drawImage(silhouette(o.img), 0, 0, o.w, o.fy, 0, 0, o.w, o.fy);
  g.restore();
}
/* colour of the light over the day, multiplied over the whole picture */
const TINT = [[0, [70, 80, 140]], [300, [80, 90, 150]], [360, [255, 186, 150]], [450, [255, 226, 198]], [600, [255, 248, 238]],
  [720, [255, 255, 255]], [900, [255, 252, 244]], [1080, [255, 224, 184]], [1200, [242, 168, 128]], [1260, [150, 128, 188]],
  [1320, [96, 100, 166]], [1440, [70, 80, 140]]];
function tintAt(min) {
  for (let i = 1; i < TINT.length; i++) {
    const [m1, c1] = TINT[i], [m0, c0] = TINT[i - 1];
    if (min <= m1) { const f = (min - m0) / (m1 - m0); return c0.map((v, j) => Math.round(v + (c1[j] - v) * f)); }
  }
  return TINT[TINT.length - 1][1];
}
/* warm glow at sunrise and sunset */
function glowAt(min) { return Math.max(0, 0.1 * (1 - Math.abs(min - 390) / 90), 0.1 * (1 - Math.abs(min - 1190) / 90)); }
function applyLight(g, w, h, min) {
  const [r, gg, b] = tintAt(min);
  g.save(); g.setTransform(1, 0, 0, 1, 0, 0);
  g.globalCompositeOperation = 'multiply'; g.fillStyle = `rgb(${r},${gg},${b})`; g.fillRect(0, 0, w, h);
  const gl = glowAt(min);
  if (gl > 0) { g.globalCompositeOperation = 'screen'; g.fillStyle = `rgba(255,160,80,${gl})`; g.fillRect(0, 0, w, h); }
  g.restore();
}


return {T, C, CROPS, SEASONS, SEASON_DAYS, seasonOf, lookFor, drawSnow, drawTrodden, drawFallen, drawSite, drawField, drawBridge, drawDitch, drawCobbles, drawFountainWater, clearCache, hash, painter, drawGrass, drawPath, drawFlowers, drawDirt, drawLocked, drawFence, drawTree, drawBush, drawWell, drawHouse, drawMarket, cropStage, drawCrop, drawSoil, drawWater, drawProduce, iconCanvas, drawPlayer,
  decoKind, fenceMask, sprite, silhouette, sunAt, castShadow, tintAt, applyLight};
})();
