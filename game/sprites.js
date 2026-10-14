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

const CROPS = {
  carrot:    {name:'Морковь',   product:'Морковь',   seedName:'Семена моркови',    seed:10,  sell:30,  grow:3,  color:'#e8832a'},
  potato:    {name:'Картофель', product:'Картофель', seedName:'Семенной картофель',seed:15,  sell:45,  grow:4,  color:'#c49a62'},
  strawberry:{name:'Клубника',  product:'Клубника',  seedName:'Рассада клубники',  seed:30,  sell:25,  grow:4,  regrow:2, color:'#d63b45'},
  tomato:    {name:'Помидор',   product:'Помидоры',  seedName:'Семена томатов',    seed:25,  sell:22,  grow:5,  regrow:2, color:'#e0402c'},
  pumpkin:   {name:'Тыква',     product:'Тыква',     seedName:'Семена тыквы',      seed:50,  sell:180, grow:7,  color:'#e98a1f'},
  apple:     {name:'Яблоня',    product:'Яблоки',    seedName:'Саженец яблони',    seed:150, sell:35,  grow:10, regrow:3, yield:3, tree:true, color:'#cf2f2f'}
};

function hash(a, b, c = 0) {
  let h = Math.imul(a | 0, 374761393) ^ Math.imul(b | 0, 668265263) ^ Math.imul(c | 0, 1274126177);
  h = Math.imul(h ^ (h >>> 13), 1274126177); h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

/* ---------- pixel drawing ---------- */
const painter = (g, X, Y) => (x, y, w, h, c) => { g.fillStyle = c; g.fillRect(X + x, Y + y, w, h); };

function drawGrass(g, x, y, base = C.grass) {
  const P = painter(g, x * T, y * T);
  P(0, 0, 16, 16, base);
  for (let i = 0; i < 6; i++) P(Math.floor(hash(x, y, i) * 15), Math.floor(hash(x, y, i + 20) * 14), 1, 2, i % 2 ? C.grassD : C.grassL);
}
function drawPath(g, x, y) {
  const P = painter(g, x * T, y * T);
  P(0, 0, 16, 16, C.path);
  for (let i = 0; i < 5; i++) P(Math.floor(hash(x, y, i + 3) * 14), Math.floor(hash(x, y, i + 30) * 14), 2, 1, i % 2 ? C.pathD : C.pathL);
}
function drawFlowers(g, x, y) { drawGrass(g, x, y); drawFlowerDots(g, x * T, y * T, x, y); }
function drawFlowerDots(g, X, Y, x, y) {
  const P = painter(g, X, Y), cols = ['#f4f1e8', '#f5d33b', '#e88bb5'];
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
/* overgrowth on uncleared land: 0 stone, 1 weeds, 2 stump */
function drawDeco(g, X, Y, v) {
  const P = painter(g, X, Y);
  if (v === 0) { P(4, 6, 7, 5, C.stone); P(4, 6, 7, 1, C.stoneL); P(5, 10, 6, 1, C.stoneD); }
  else if (v === 1) { P(3, 4, 1, 6, C.leafD); P(5, 2, 1, 8, C.leafD); P(7, 5, 1, 5, C.leafD); P(10, 7, 1, 5, C.leafD); P(12, 5, 1, 6, C.leafD); }
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
function drawTree(g, v = 0) {
  const P = painter(g, 0, 0);
  if (v === 1) {
    P(14, 23, 4, 17, C.trunk); P(14, 23, 1, 17, C.trunkD); P(12, 38, 8, 2, C.trunk);
    P(8, 3, 16, 20, C.leaf); P(6, 8, 20, 12, C.leaf); P(11, 1, 10, 2, C.leaf); P(10, 23, 12, 2, C.leaf);
    P(6, 18, 20, 2, C.leafD); P(21, 6, 4, 13, C.leafD); P(10, 24, 12, 1, C.leafD);
    P(10, 4, 5, 3, C.leafL); P(8, 9, 4, 4, C.leafL); P(14, 7, 3, 2, C.leafL);
    P(16, 12, 2, 1, C.leafD); P(11, 15, 2, 1, C.leafD); P(18, 9, 1, 2, C.leafD);
    return;
  }
  P(13, 27, 6, 13, C.trunk); P(13, 27, 2, 13, C.trunkD); P(11, 38, 10, 2, C.trunk); P(11, 38, 2, 2, C.trunkD);
  P(5, 8, 22, 15, C.leaf); P(3, 11, 26, 9, C.leaf); P(8, 4, 16, 5, C.leaf); P(11, 2, 10, 2, C.leaf);
  P(7, 22, 18, 4, C.leaf); P(10, 26, 12, 2, C.leaf);
  P(3, 18, 26, 2, C.leafD); P(7, 24, 18, 2, C.leafD); P(24, 10, 4, 9, C.leafD); P(10, 27, 12, 1, C.leafD);
  P(9, 5, 7, 3, C.leafL); P(6, 9, 6, 4, C.leafL); P(13, 8, 4, 2, C.leafL); P(5, 13, 3, 3, C.leafL);
  P(15, 13, 2, 1, C.leafD); P(20, 8, 1, 2, C.leafD); P(11, 16, 2, 1, C.leafD); P(19, 19, 2, 1, C.leafD);
}
function drawBush(g) {
  const P = painter(g, 0, 0), r = '#d63b45';
  P(3, 4, 14, 10, C.leaf); P(1, 6, 18, 7, C.leaf); P(5, 2, 10, 2, C.leaf);
  P(6, 3, 5, 2, C.leafL); P(3, 6, 3, 2, C.leafL); P(2, 12, 16, 2, C.leafD); P(15, 6, 2, 6, C.leafD);
  P(6, 7, 2, 2, r); P(12, 9, 2, 2, r); P(8, 11, 2, 2, r); P(6, 7, 1, 1, '#f07070'); P(12, 9, 1, 1, '#f07070');
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
function drawWater(g, x, y, sec, edgeTop) {
  const P = painter(g, x * T, y * T);
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
  if (k === 'apple') {
    if (st === 0) { P(7, 6, 2, 10, C.trunk); P(5, 5, 3, 2, C.leafL); P(9, 3, 3, 2, C.leafL); P(8, 8, 3, 1, C.leaf); return; }
    if (st === 1) {
      P(7, 2, 2, 14, C.trunk); P(7, 2, 1, 14, C.trunkD);
      P(2, -8, 12, 11, C.leaf); P(1, -5, 14, 6, C.leaf); P(4, -10, 8, 2, C.leaf);
      P(4, -8, 4, 2, C.leafL); P(2, -4, 3, 2, C.leafL); P(2, 1, 12, 2, C.leafD); P(12, -6, 2, 6, C.leafD);
      return;
    }
    P(6, -2, 4, 18, C.trunk); P(6, -2, 1, 18, C.trunkD); P(4, 14, 8, 2, C.trunk);
    P(-4, -22, 24, 18, C.leaf); P(-6, -18, 28, 11, C.leaf); P(0, -25, 16, 3, C.leaf); P(-2, -5, 20, 3, C.leaf);
    P(-6, -9, 28, 2, C.leafD); P(14, -20, 6, 12, C.leafD); P(0, -3, 16, 1, C.leafD);
    P(0, -23, 8, 3, C.leafL); P(-4, -18, 5, 4, C.leafL); P(5, -19, 3, 2, C.leafL);
    if (st === 3) [[-2, -14], [5, -20], [12, -12], [2, -8], [9, -16], [15, -7], [-4, -8]].forEach(([a, b]) => { P(a, b, 3, 3, d.color); P(a, b, 1, 1, '#f07070'); });
    return;
  }
  if (st === 0) { P(4, 9, 2, 2, '#4a2c16'); P(9, 8, 2, 2, '#4a2c16'); P(7, 11, 2, 1, '#4a2c16'); return; }
  if (st === 1) { P(7, 7, 2, 6, C.leaf); P(5, 6, 2, 2, C.leafL); P(9, 5, 2, 2, C.leafL); return; }
  if (st === 2) {
    if (k === 'pumpkin') { P(0, 10, 16, 2, C.leaf); P(1, 6, 4, 4, C.leafL); P(11, 6, 4, 4, C.leafL); P(7, 8, 2, 2, '#f5c84a'); return; }
    if (k === 'tomato') { P(7, -6, 2, 20, '#a07a4a'); P(4, -2, 8, 6, C.leaf); P(5, 4, 6, 6, C.leaf); P(3, 0, 3, 3, C.leafL); P(10, 3, 3, 3, C.leafL); return; }
    P(7, 3, 2, 10, C.leaf); P(4, 2, 3, 3, C.leafL); P(9, 0, 3, 3, C.leafL); P(3, 7, 3, 2, C.leaf); P(10, 6, 3, 2, C.leaf);
    return;
  }
  if (k === 'carrot') {
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

/* icons */
function drawProduce(g, k, ox = 2, oy = 2) {
  const P = painter(g, ox, oy), c = CROPS[k].color;
  if (k === 'carrot') { P(8, 0, 2, 3, C.leafL); P(10, 1, 2, 2, C.leaf); P(6, 3, 4, 3, c); P(4, 5, 4, 3, c); P(3, 7, 3, 2, c); P(2, 9, 2, 2, c); P(1, 11, 1, 1, c); P(7, 3, 1, 1, '#f6a85a'); }
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
    for (let i = 0; i < 10; i++) P(2 + i, 13 - i, 2, 2, C.trunk);
    P(9, 1, 6, 3, '#9aa3ad'); P(12, 4, 3, 3, '#9aa3ad'); P(9, 1, 6, 1, '#c9d0d6');
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
function sprite(kind, a, b) {
  switch (kind) {
    case 'tree':   return cached('tree' + a, 32, 40, 16, 40, g => drawTree(g, a));
    case 'bush':   return cached('bush', 20, 16, 10, 16, g => drawBush(g));
    case 'well':   return cached('well', 16, 28, 8, 28, g => drawWell(g));
    case 'house':  return cached('house' + (a ? 1 : 0), 64, 60, 0, 60, g => {
      const P = painter(g, 0, 0);
      P(46, 0, 7, 16, '#7d7d74'); P(46, 0, 7, 2, '#9d9d92'); P(51, 2, 2, 14, '#626259');
      drawHouse(g, a, 0, 12 / T);
    });
    case 'market': return cached('market', 80, 48, 0, 48, g => drawMarket(g, 0, 0));
    case 'player': return cached('player' + a + b, 16, 24, 8, 24, g => drawPlayer(g, 0, 0, a, b));
    case 'crop':   return cached('crop' + a + b, 32, 44, 16, 44, g => drawCrop(g, 8, 28, a, b));
    case 'fence':  return cached('fence' + a, 16, 16, 8, 16, g => drawFencePiece(g, 0, 0, a));
    case 'deco':   return cached('deco' + a, 16, 16, 8, 16, g => drawDeco(g, 0, 0, a));
    case 'flower': return cached('flower' + a + ',' + b, 16, 16, 8, 16, g => drawFlowerDots(g, 0, 0, a, b));
  }
  return null;
}
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
function castShadow(g, o, px, py, sun) {
  const foot = py - o.ay + o.fy;
  g.save();
  g.transform(1, 0, -sun.shear, -sun.len, px - o.ax + sun.shear * o.fy, foot + sun.len * o.fy);
  g.drawImage(silhouette(o.img), 0, 0);
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


return {T, C, CROPS, hash, painter, drawGrass, drawPath, drawFlowers, drawDirt, drawLocked, drawFence, drawTree, drawBush, drawWell, drawHouse, drawMarket, cropStage, drawCrop, drawSoil, drawWater, drawProduce, iconCanvas, drawPlayer,
  decoKind, fenceMask, sprite, silhouette, sunAt, castShadow, tintAt, applyLight};
})();
