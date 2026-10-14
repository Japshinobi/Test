/* Дедушкин огород: все спрайты игры.
   Общий файл для игры (index.html) и каталога графики (catalog.html).
   Клетка 16x16 пикселей; каждая функция рисует пиксели прямоугольниками. */
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
function drawFlowers(g, x, y) {
  drawGrass(g, x, y);
  const P = painter(g, x * T, y * T), cols = ['#f4f1e8', '#f5d33b', '#e88bb5'];
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
function drawLocked(g, x, y) {
  drawGrass(g, x, y);
  const P = painter(g, x * T, y * T), r = hash(x, y, 9);
  if (r < 0.35) { P(4, 6, 7, 5, C.stone); P(4, 6, 7, 1, C.stoneL); P(5, 10, 6, 1, C.stoneD); }
  else if (r < 0.7) { P(3, 4, 1, 6, C.leafD); P(5, 2, 1, 8, C.leafD); P(7, 5, 1, 5, C.leafD); P(10, 7, 1, 5, C.leafD); P(12, 5, 1, 6, C.leafD); }
  else { P(5, 8, 6, 5, C.trunk); P(5, 8, 6, 2, '#a0784f'); P(7, 8, 2, 1, C.trunkD); }
}
function drawFence(g, x, y, is) {
  drawGrass(g, x, y);
  const P = painter(g, x * T, y * T);
  if (is(x - 1, y)) { P(0, 6, 8, 2, C.fence); P(0, 10, 8, 2, C.fence); }
  if (is(x + 1, y)) { P(8, 6, 8, 2, C.fence); P(8, 10, 8, 2, C.fence); }
  if (is(x, y - 1)) P(7, 0, 2, 6, C.fence);
  if (is(x, y + 1)) P(7, 12, 2, 4, C.fence);
  P(5, 3, 6, 11, C.fence); P(5, 3, 6, 1, C.fenceL); P(5, 13, 6, 1, C.fenceD); P(10, 4, 1, 9, C.fenceD);
}
function drawTree(g, x, y) {
  drawGrass(g, x, y);
  const P = painter(g, x * T, y * T);
  P(3, 13, 10, 2, 'rgba(0,0,0,.18)');
  P(6, 10, 4, 6, C.trunk); P(6, 10, 1, 6, C.trunkD);
  P(2, 2, 12, 9, C.leaf); P(1, 4, 14, 5, C.leaf); P(4, 1, 8, 1, C.leaf);
  P(4, 3, 4, 2, C.leafL); P(3, 5, 2, 2, C.leafL); P(2, 9, 12, 2, C.leafD);
}
function drawBush(g, x, y) {
  drawGrass(g, x, y);
  const P = painter(g, x * T, y * T);
  P(2, 6, 12, 8, C.leaf); P(3, 5, 10, 2, C.leafL); P(1, 8, 14, 4, C.leaf); P(3, 12, 10, 2, C.leafD);
  P(5, 8, 1, 1, '#d63b45'); P(10, 9, 1, 1, '#d63b45'); P(7, 11, 1, 1, '#d63b45');
}
function drawWell(g, x, y) {
  drawGrass(g, x, y);
  const P = painter(g, x * T, y * T);
  P(2, 8, 12, 7, C.stone); P(2, 8, 12, 1, C.stoneL); P(4, 12, 2, 1, C.stoneD); P(9, 13, 3, 1, C.stoneD); P(7, 11, 2, 1, C.stoneD);
  P(4, 9, 8, 2, '#2a4f78');
  P(3, 2, 2, 7, C.trunk); P(11, 2, 2, 7, C.trunk);
  P(1, 1, 14, 2, '#7a4a26'); P(2, 0, 12, 1, '#9a6a3a');
  P(7, 3, 1, 4, '#d9c9a0'); P(6, 7, 3, 2, '#8b8b8b');
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
  const P = painter(g, X, Y), d = CROPS[k];
  if (k === 'apple') {
    if (st === 0) { P(7, 7, 2, 8, C.trunk); P(5, 6, 3, 2, C.leafL); P(9, 5, 3, 2, C.leafL); return; }
    if (st === 1) { P(7, 8, 2, 7, C.trunk); P(4, 1, 8, 8, C.leaf); P(5, 2, 3, 2, C.leafL); P(4, 7, 8, 2, C.leafD); return; }
    P(3, 13, 10, 2, 'rgba(0,0,0,.2)');
    P(6, 8, 4, 8, C.trunk); P(6, 8, 1, 8, C.trunkD);
    P(1, -6, 14, 14, C.leaf); P(0, -3, 16, 8, C.leaf); P(3, -8, 10, 2, C.leaf);
    P(3, -5, 4, 3, C.leafL); P(1, 5, 14, 3, C.leafD);
    if (st === 3) [[3, -2], [9, -5], [11, 1], [5, 3], [7, -1]].forEach(([a, b]) => { P(a, b, 3, 3, d.color); P(a, b, 1, 1, '#f07070'); });
    return;
  }
  if (st === 0) { P(4, 9, 2, 2, '#4a2c16'); P(9, 8, 2, 2, '#4a2c16'); P(7, 11, 2, 1, '#4a2c16'); return; }
  if (st === 1) { P(7, 8, 2, 5, C.leaf); P(5, 7, 2, 2, C.leafL); P(9, 7, 2, 2, C.leafL); return; }
  if (st === 2) {
    if (k === 'pumpkin') { P(1, 10, 14, 2, C.leaf); P(2, 7, 4, 3, C.leafL); P(10, 7, 4, 3, C.leafL); P(7, 9, 2, 2, '#f5c84a'); return; }
    if (k === 'tomato') P(7, 2, 2, 12, '#a07a4a');
    P(7, 6, 2, 7, C.leaf); P(4, 5, 3, 3, C.leafL); P(9, 4, 3, 3, C.leafL); P(4, 9, 3, 2, C.leaf); P(9, 8, 3, 2, C.leaf);
    return;
  }
  if (k === 'carrot') {
    P(5, 2, 2, 6, C.leaf); P(8, 1, 2, 7, C.leafL); P(10, 3, 2, 5, C.leaf);
    P(5, 8, 6, 4, d.color); P(6, 12, 4, 2, '#d06a1c'); P(7, 14, 2, 1, '#d06a1c');
  } else if (k === 'potato') {
    P(3, 5, 10, 7, C.leaf); P(4, 4, 8, 2, C.leafL); P(5, 3, 2, 2, '#c9a6e8'); P(10, 5, 2, 2, '#f3f0ff');
    P(2, 12, 4, 3, d.color); P(10, 12, 4, 3, d.color); P(6, 13, 3, 2, '#a87f4c');
  } else if (k === 'strawberry') {
    P(2, 8, 12, 5, C.leaf); P(3, 7, 4, 2, C.leafL); P(9, 7, 4, 2, C.leafL);
    [[3, 11], [9, 10], [6, 12]].forEach(([a, b]) => { P(a, b, 3, 3, d.color); P(a + 1, b + 1, 1, 1, '#f5d33b'); });
  } else if (k === 'tomato') {
    P(7, 1, 2, 14, '#a07a4a'); P(4, 3, 8, 9, C.leaf); P(3, 6, 10, 4, C.leafL);
    [[4, 5], [9, 7], [5, 10]].forEach(([a, b]) => { P(a, b, 3, 3, d.color); P(a, b, 1, 1, '#ff8a70'); });
  } else if (k === 'pumpkin') {
    P(1, 12, 14, 2, C.leaf); P(1, 6, 4, 3, C.leafL);
    P(3, 6, 10, 8, d.color); P(2, 8, 12, 5, d.color);
    P(5, 7, 1, 6, '#c46d10'); P(8, 6, 1, 8, '#c46d10'); P(11, 7, 1, 6, '#c46d10'); P(7, 4, 2, 3, '#5a7a2a');
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


/* player */
function drawPlayer(g, X, Y, face, frame) {
  const P = painter(g, X, Y - (frame ? 1 : 0));
  const skin = '#f2c39b', hat = '#e3c069', band = '#9c6b2f', shirt = '#c0563a', over = '#3d5a8c', boot = '#4a2f1d', hair = '#7a4a22';
  g.fillStyle = 'rgba(0,0,0,.22)'; g.fillRect(X + 4, Y + 14, 8, 2);
  const l = frame ? 1 : 0;
  P(5, 13 - l, 2, 3, boot); P(9, 13 - (frame ? 0 : 1) + (frame ? 0 : 1), 2, 3, boot);
  P(4, 9, 8, 4, shirt); P(5, 10, 6, 4, over); P(6, 9, 1, 1, over); P(9, 9, 1, 1, over);
  if (face === 'left') { P(5, 10, 2, 3, skin); }
  else if (face === 'right') { P(9, 10, 2, 3, skin); }
  else { P(3, 10, 1, 3, skin); P(12, 10, 1, 3, skin); }
  P(4, 4, 8, 5, skin);
  if (face === 'up') P(4, 4, 8, 4, hair);
  else if (face === 'down') { P(6, 6, 1, 2, C.ink); P(9, 6, 1, 2, C.ink); P(4, 4, 8, 1, hair); }
  else if (face === 'left') { P(5, 6, 1, 2, C.ink); P(8, 4, 4, 3, hair); }
  else { P(10, 6, 1, 2, C.ink); P(4, 4, 4, 3, hair); }
  P(2, 3, 12, 2, hat); P(4, 1, 8, 2, hat); P(4, 3, 8, 1, band);
}


return {T, C, CROPS, hash, painter, drawGrass, drawPath, drawFlowers, drawDirt, drawLocked, drawFence, drawTree, drawBush, drawWell, drawHouse, drawMarket, cropStage, drawCrop, drawSoil, drawWater, drawProduce, iconCanvas, drawPlayer};
})();
