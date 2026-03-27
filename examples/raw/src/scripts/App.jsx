import Stigma, { Window } from "stigma";
import {
  Scene, Cube, Sphere, Cylinder, Vector3, Input, GUI, Configuration,
  Debug, PointLight, Particles, Audio,
} from "tachyon";

let gt = 0, mx = 0, my = 0, mDown = false, mWas = false, mClick = false;
let fontId = 0;
let fontBigId = 0;

function updateMouse() {
  let p = Input.mousePosition();
  mx = p.x; my = p.y; mWas = mDown;
  mDown = Input.mouseButtonDown(0); mClick = mDown && !mWas;
}
function hit(x, y, w, h) { return mx >= x && mx < x + w && my >= y && my < y + h; }
function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }

let W = 1920, H = 1080, GW = 8;
function tw(s, sc) { return s.length * GW * sc; }
function txc(s, sc, x, w) { return x + (w - tw(s, sc)) / 2; }
function R(x, y, w, h, r, g, b, a) { GUI.rect(x, y, w, h, r, g, b, a); }

function T(s, x, y, sc, r, g, b, a) {
  GUI.text(s, x, y, sc, r, g, b, a);
}
function Tbig(s, x, y, sc, r, g, b, a) {
  GUI.text(s, x, y, sc, r, g, b, a);
}
function Tc(s, sc, bx, bw, y, r, g, b, a) { T(s, txc(s, sc, bx, bw), y, sc, r, g, b, a); }
function TcBig(s, sc, bx, bw, y, r, g, b, a) { Tbig(s, txc(s, sc, bx, bw), y, sc, r, g, b, a); }

// Vibrant palette — dark bg, bright accents, high contrast
let C = {
  bg:      [0.06, 0.06, 0.08],
  panel:   [0.09, 0.09, 0.12],
  panelLt: [0.12, 0.12, 0.16],
  card:    [0.10, 0.10, 0.14],
  cardHov: [0.14, 0.14, 0.19],
  border:  [0.22, 0.22, 0.28],
  accent:  [0.95, 0.55, 0.10],   // warm orange
  accentH: [1.00, 0.70, 0.25],
  accentD: [0.60, 0.35, 0.08],
  blue:    [0.20, 0.55, 1.00],
  blueH:   [0.35, 0.70, 1.00],
  blueD:   [0.12, 0.30, 0.60],
  green:   [0.20, 0.82, 0.40],
  greenD:  [0.10, 0.45, 0.20],
  red:     [0.90, 0.22, 0.18],
  redH:    [1.00, 0.35, 0.28],
  cyan:    [0.15, 0.85, 0.90],
  purple:  [0.65, 0.35, 0.95],
  white:   [1.00, 1.00, 1.00],
  text:    [0.92, 0.92, 0.95],
  textDim: [0.50, 0.50, 0.58],
  textOff: [0.35, 0.35, 0.40],
};

function box(x, y, w, h, c, a) { R(x, y, w, h, c[0], c[1], c[2], a); }
function lbl(s, x, y, sc, c, a) { T(s, x, y, sc, c[0], c[1], c[2], a); }
function lblC(s, sc, bx, bw, y, c, a) { Tc(s, sc, bx, bw, y, c[0], c[1], c[2], a); }
function lblCBig(s, sc, bx, bw, y, c, a) { TcBig(s, sc, bx, bw, y, c[0], c[1], c[2], a); }

function accentLine(x, y, w) { R(x, y, w, 2, C.accent[0], C.accent[1], C.accent[2], 0.8); }
function subtleBorder(x, y, w, h) {
  R(x, y, w, 1, C.border[0], C.border[1], C.border[2], 0.3);
  R(x, y+h-1, w, 1, C.border[0], C.border[1], C.border[2], 0.15);
  R(x, y, 1, h, C.border[0], C.border[1], C.border[2], 0.2);
  R(x+w-1, y, 1, h, C.border[0], C.border[1], C.border[2], 0.1);
}

// State
let state = "menu";
let optionsTab = 0;
let opts = {
  shadows: true, ssao: true, bloom: true, fxaa: true,
  vsync: true, fullscreen: true, vignette: false, chromatic: false,
  resolution: 2, shadowQual: 0.75, gamma: 0.5, fov: 0.6,
  masterVol: 0.8, sfxVol: 0.7, musicVol: 0.6,
};
let bindings = [
  { action: "Move Left", key: "A" }, { action: "Move Right", key: "D" },
  { action: "Jump", key: "SPACE" }, { action: "Sprint", key: "SHIFT" },
  { action: "Interact", key: "E" }, { action: "Pause", key: "ESCAPE" },
  { action: "Camera Up", key: "W" }, { action: "Camera Down", key: "S" },
];
let rebinding = -1;

// Platformer
let player = { x: 200, y: 600, vx: 0, vy: 0, w: 32, h: 40, grounded: false, facing: 1, jumps: 0 };
let cam = { x: 0 };
let platforms = [], coins = [], enemies = [];
let score = 0, lives = 3, level = 1;
let deathTimer = 0, winTimer = 0, gameOverTimer = 0;

function generateLevel() {
  platforms = []; coins = []; enemies = []; score = 0;
  platforms.push({ x: -200, y: 780, w: 6000, h: 40, c: C.panelLt });
  let px = 300;
  for (let i = 0; i < 25; i++) {
    let pw = 120 + Math.floor(Math.random() * 180);
    let py = 600 - Math.floor(Math.random() * 300);
    platforms.push({ x: px, y: py, w: pw, h: 20, c: i % 3 === 0 ? C.blue : C.panelLt });
    for (let c = 0; c < 1 + Math.floor(Math.random() * 3); c++)
      coins.push({ x: px + 20 + c * 30, y: py - 30, collected: false });
    if (Math.random() > 0.6 && i > 2)
      enemies.push({ x: px + pw / 2, y: py - 28, w: 24, h: 24, vx: 30, minX: px, maxX: px + pw - 24, alive: true });
    px += pw + 80 + Math.floor(Math.random() * 150);
  }
  for (let i = 0; i < 15; i++) coins.push({ x: 400 + i * 250 + Math.random() * 100, y: 300 + Math.random() * 200, collected: false });
  platforms.push({ x: px + 100, y: 500, w: 80, h: 280, c: C.accent, isGoal: true });
  player.x = 200; player.y = 600; player.vx = 0; player.vy = 0;
  player.grounded = false; player.jumps = 0; cam.x = 0;
  deathTimer = 0; winTimer = 0;
}

// Big vibrant button
function bigBtn(x, y, w, h, label, color, hoverColor) {
  let hov = hit(x, y, w, h);
  let bg = hov ? hoverColor : color;
  box(x, y, w, h, bg, 0.95);
  if (hov) {
    R(x, y, w, 2, C.white[0], C.white[1], C.white[2], 0.15);
    R(x, y, w, h, C.white[0], C.white[1], C.white[2], 0.04);
  }
  R(x, y+h-1, w, 1, 0, 0, 0, 0.3);
  lblC(label, 1.6, x, w, y + h/2 - 8, C.white, hov ? 1 : 0.92);
  return hov && mClick;
}

// Card-style menu button with left accent bar
function menuBtn(x, y, w, h, label, acColor) {
  let hov = hit(x, y, w, h);
  box(x, y, w, h, hov ? C.cardHov : C.card, 0.92);
  R(x, y, 4, h, acColor[0], acColor[1], acColor[2], hov ? 1 : 0.6);
  subtleBorder(x, y, w, h);
  if (hov) R(x+4, y, w-4, h, acColor[0], acColor[1], acColor[2], 0.05);
  lbl(label, x + 24, y + h/2 - 8, 1.5, hov ? C.white : C.text, hov ? 1 : 0.85);
  return hov && mClick;
}

function toggle(x, y, label, val) {
  let hov = hit(x, y, 420, 28);
  lbl(label, x, y + 4, 1.2, C.text, 0.9);
  let bx = x + 300, bw = 70, bh = 28;
  box(bx, y, bw, bh, val ? C.green : C.panel, 0.9);
  subtleBorder(bx, y, bw, bh);
  if (val) {
    R(bx, y, bw, 1, C.green[0], C.green[1], C.green[2], 0.3);
    lblC("ON", 1.1, bx, bw, y + 6, C.white, 1);
  } else {
    lblC("OFF", 1.1, bx, bw, y + 6, C.textOff, 0.6);
  }
  if (hov) box(bx, y, bw, bh, C.white, 0.04);
  return (hov && mClick) ? !val : val;
}

function slider(x, y, label, val, suffix) {
  lbl(label, x, y + 2, 1.2, C.text, 0.9);
  let sx = x + 300, sw = 240, sh = 14;
  box(sx, y + 4, sw, sh, C.bg, 0.95);
  subtleBorder(sx, y + 4, sw, sh);
  let fill = (sw - 4) * clamp(val, 0, 1);
  if (fill > 0) R(sx + 2, y + 6, fill, sh - 4, C.accent[0], C.accent[1], C.accent[2], 0.7);
  R(sx + 2 + fill - 4, y + 2, 8, sh + 4, C.accentH[0], C.accentH[1], C.accentH[2], 0.95);
  R(sx + 2 + fill - 3, y + 3, 6, 1, C.white[0], C.white[1], C.white[2], 0.3);
  let hov = hit(sx, y, sw, sh + 8);
  if (hov && mDown) val = clamp((mx - sx - 2) / (sw - 4), 0, 1);
  lbl(suffix || Math.round(val * 100) + "%", sx + sw + 14, y + 2, 1.1, C.accent, 0.85);
  return val;
}

function backBtn(px, py, pw) {
  let bx = px + pw - 100, by = py + 8;
  let hov = hit(bx, by, 86, 28);
  box(bx, by, 86, 28, hov ? C.cardHov : C.panel, 0.9);
  subtleBorder(bx, by, 86, 28);
  lblC("BACK", 1.1, bx, 86, by + 6, hov ? C.accent : C.text, 0.85);
  return (hov && mClick) || Input.keyPressed("Escape");
}

function drawMenu() {
  // Full screen dark with subtle gradient
  box(0, 0, W, H, C.bg, 0.65);

  // Center everything
  let centerX = W / 2;
  let panelW = 460;
  let panelX = centerX - panelW / 2;
  let panelY = 160;
  let panelH = 620;

  // Main card
  box(panelX, panelY, panelW, panelH, C.panel, 0.94);
  subtleBorder(panelX, panelY, panelW, panelH);

  // Top accent line
  accentLine(panelX, panelY, panelW);

  // Title area
  lblCBig("RAW", 3.0, panelX, panelW, panelY + 24, C.accent, 1);
  lblCBig("ADVENTURES", 1.6, panelX, panelW, panelY + 75, C.white, 0.9);

  // Divider
  R(panelX + 60, panelY + 110, panelW - 120, 1, C.border[0], C.border[1], C.border[2], 0.3);

  // Buttons
  let btnX = panelX + 30;
  let btnW = panelW - 60;
  let btnH = 56;
  let btnY = panelY + 135;
  let btnGap = 12;

  if (bigBtn(btnX, btnY, btnW, btnH, "PLAY", C.accent, C.accentH)) {
    state = "playing"; lives = 3; level = 1; generateLevel();
  }
  btnY += btnH + btnGap + 8;

  if (menuBtn(btnX, btnY, btnW, 50, "OPTIONS", C.blue)) {
    state = "options"; optionsTab = 0;
  }
  btnY += 50 + btnGap;

  if (menuBtn(btnX, btnY, btnW, 50, "CONTROLS", C.purple)) {
    state = "controls"; rebinding = -1;
  }
  btnY += 50 + btnGap;

  if (menuBtn(btnX, btnY, btnW, 50, "QUIT", C.red)) {
    Debug.log("QUIT_REQUESTED");
  }

  // Footer
  R(panelX + 60, panelY + panelH - 50, panelW - 120, 1, C.border[0], C.border[1], C.border[2], 0.2);
  lblC("v0.1.0", 0.9, panelX, panelW, panelY + panelH - 35, C.textOff, 0.4);

  // Bottom screen bar
  box(0, H - 28, W, 28, C.bg, 0.95);
  R(0, H - 28, W, 1, C.border[0], C.border[1], C.border[2], 0.25);
  lbl("RAW Adventures", 12, H - 22, 0.9, C.accentD, 0.6);
  lbl("2026", W - 50, H - 22, 0.9, C.textOff, 0.4);
}

function drawOptions() {
  box(0, 0, W, H, C.bg, 0.65);

  let px = W / 2 - 380, py = 80, pw = 760, ph = 780;
  box(px, py, pw, ph, C.panel, 0.95);
  subtleBorder(px, py, pw, ph);
  accentLine(px, py, pw);

  // Header
  box(px, py, pw, 44, C.panelLt, 0.95);
  lblC("OPTIONS", 2.0, px, pw, py + 8, C.blue, 1);

  if (backBtn(px, py, pw)) state = "menu";

  // Tabs
  let tabs = ["GRAPHICS", "AUDIO", "DISPLAY"];
  let tabColors = [C.accent, C.green, C.blue];
  let tabW = Math.floor((pw - 40) / tabs.length);
  for (let i = 0; i < tabs.length; i++) {
    let tx = px + 20 + i * tabW;
    let tHov = hit(tx, py + 54, tabW - 8, 32);
    let tA = i === optionsTab;
    if (tHov && mClick) optionsTab = i;
    box(tx, py + 54, tabW - 8, 32, tA ? C.panelLt : C.bg, 0.85);
    if (tA) R(tx, py + 84, tabW - 8, 3, tabColors[i][0], tabColors[i][1], tabColors[i][2], 0.9);
    lblC(tabs[i], 1.2, tx, tabW - 8, py + 62, tA ? tabColors[i] : C.textDim, tA ? 1 : 0.5);
  }

  let cy = py + 105, cx = px + 50;

  if (optionsTab === 0) {
    lbl("RENDERING", cx, cy, 1.0, C.accent, 0.7); cy += 28;
    R(cx, cy - 6, pw - 100, 1, C.border[0], C.border[1], C.border[2], 0.2); cy += 4;
    opts.shadows = toggle(cx, cy, "Shadows", opts.shadows); cy += 36;
    opts.ssao = toggle(cx, cy, "Ambient Occlusion", opts.ssao); cy += 36;
    opts.bloom = toggle(cx, cy, "Bloom", opts.bloom); cy += 36;
    opts.fxaa = toggle(cx, cy, "Anti-Aliasing", opts.fxaa); cy += 36;
    opts.vignette = toggle(cx, cy, "Vignette", opts.vignette); cy += 36;
    opts.chromatic = toggle(cx, cy, "Chromatic Aberration", opts.chromatic); cy += 36;
    cy += 12;
    lbl("QUALITY", cx, cy, 1.0, C.accent, 0.7); cy += 28;
    R(cx, cy - 6, pw - 100, 1, C.border[0], C.border[1], C.border[2], 0.2); cy += 4;
    opts.shadowQual = slider(cx, cy, "Shadow Quality", opts.shadowQual); cy += 36;
    opts.gamma = slider(cx, cy, "Gamma", opts.gamma, (0.5 + opts.gamma * 2).toFixed(1)); cy += 36;
    opts.fov = slider(cx, cy, "Field of View", opts.fov, Math.round(60 + opts.fov * 60).toString()); cy += 36;

    let apX = px + pw / 2 - 90, apY = py + ph - 60;
    if (bigBtn(apX, apY, 180, 40, "APPLY", C.accent, C.accentH)) Debug.log("Options applied");
  } else if (optionsTab === 1) {
    lbl("VOLUME", cx, cy, 1.0, C.green, 0.7); cy += 28;
    R(cx, cy - 6, pw - 100, 1, C.border[0], C.border[1], C.border[2], 0.2); cy += 4;
    opts.masterVol = slider(cx, cy, "Master Volume", opts.masterVol); cy += 42;
    opts.sfxVol = slider(cx, cy, "SFX Volume", opts.sfxVol); cy += 42;
    opts.musicVol = slider(cx, cy, "Music Volume", opts.musicVol); cy += 42;
    cy += 20;
    lbl("Volumes save automatically", cx, cy, 1.0, C.textOff, 0.4);
  } else {
    lbl("DISPLAY", cx, cy, 1.0, C.blue, 0.7); cy += 28;
    R(cx, cy - 6, pw - 100, 1, C.border[0], C.border[1], C.border[2], 0.2); cy += 4;
    opts.vsync = toggle(cx, cy, "VSync", opts.vsync); cy += 36;
    opts.fullscreen = toggle(cx, cy, "Fullscreen", opts.fullscreen); cy += 36;
    cy += 16;
    lbl("RESOLUTION", cx, cy, 1.0, C.blue, 0.7); cy += 28;
    let res = ["1280x720", "1600x900", "1920x1080", "2560x1440"];
    for (let i = 0; i < res.length; i++) {
      let rx = cx + i * 160;
      let rHov = hit(rx, cy, 148, 32);
      let rA = i === opts.resolution;
      box(rx, cy, 148, 32, rA ? C.panelLt : C.bg, 0.9);
      subtleBorder(rx, cy, 148, 32);
      if (rA) R(rx, cy + 30, 148, 2, C.blue[0], C.blue[1], C.blue[2], 0.8);
      if (rHov && mClick) opts.resolution = i;
      lblC(res[i], 1.1, rx, 148, cy + 8, rA ? C.blue : C.textDim, rA ? 1 : 0.55);
    }
  }
}

function drawControls() {
  box(0, 0, W, H, C.bg, 0.65);

  let px = W / 2 - 360, py = 100, pw = 720, ph = 680;
  box(px, py, pw, ph, C.panel, 0.95);
  subtleBorder(px, py, pw, ph);
  accentLine(px, py, pw);

  box(px, py, pw, 44, C.panelLt, 0.95);
  lblC("CONTROLS", 2.0, px, pw, py + 8, C.purple, 1);

  if (backBtn(px, py, pw)) { state = "menu"; rebinding = -1; }

  let cy = py + 58;
  lbl("ACTION", px + 40, cy, 1.0, C.textDim, 0.5);
  lbl("BINDING", px + 400, cy, 1.0, C.textDim, 0.5);
  cy += 24;
  R(px + 30, cy, pw - 60, 1, C.border[0], C.border[1], C.border[2], 0.25);
  cy += 10;

  for (let i = 0; i < bindings.length; i++) {
    let b = bindings[i];
    let rowHov = hit(px + 30, cy, pw - 60, 42);
    if (i % 2 === 0) box(px + 30, cy, pw - 60, 42, C.bg, 0.3);
    if (rowHov) box(px + 30, cy, pw - 60, 42, C.purple, 0.04);

    lbl(b.action, px + 40, cy + 10, 1.2, C.text, 0.9);

    let kx = px + 390, kw = 180, kh = 32;
    let kHov = hit(kx, cy + 5, kw, kh);

    if (rebinding === i) {
      box(kx, cy + 5, kw, kh, C.bg, 0.95);
      R(kx, cy + 5, kw, kh, C.purple[0], C.purple[1], C.purple[2], 0.2);
      subtleBorder(kx, cy + 5, kw, kh);
      let blink = Math.floor(gt * 3) % 2 === 0;
      if (blink) lblC("PRESS KEY...", 1.0, kx, kw, cy + 12, C.purple, 1);
    } else {
      box(kx, cy + 5, kw, kh, kHov ? C.cardHov : C.card, 0.9);
      subtleBorder(kx, cy + 5, kw, kh);
      if (kHov) R(kx, cy + 5, 3, kh, C.purple[0], C.purple[1], C.purple[2], 0.8);
      lblC(b.key, 1.2, kx, kw, cy + 12, kHov ? C.white : C.text, 0.9);
    }
    if (kHov && mClick && rebinding !== i) rebinding = i;

    cy += 44;
  }

  if (rebinding >= 0) lbl("Press any key to rebind, or ESC to cancel", px + 40, py + ph - 46, 1.0, C.purple, 0.6);

  let rdX = px + pw / 2 - 100, rdY = py + ph - 54;
  let rdHov = hit(rdX, rdY, 200, 34);
  box(rdX, rdY, 200, 34, rdHov ? C.cardHov : C.card, 0.9);
  subtleBorder(rdX, rdY, 200, 34);
  lblC("RESET DEFAULTS", 1.1, rdX, 200, rdY + 8, rdHov ? C.white : C.textDim, 0.75);
}

function updatePlatformer(dt) {
  if (deathTimer > 0) { deathTimer -= dt; if (deathTimer <= 0) { if (lives <= 0) gameOverTimer = 3; else { player.x = 200; player.y = 600; player.vx = 0; player.vy = 0; } } return; }
  if (gameOverTimer > 0) { gameOverTimer -= dt; if (gameOverTimer <= 0) state = "menu"; return; }
  if (winTimer > 0) { winTimer -= dt; if (winTimer <= 0) { level++; generateLevel(); } return; }

  let moveL = Input.keyDown("A") || Input.keyDown("ArrowLeft");
  let moveR = Input.keyDown("D") || Input.keyDown("ArrowRight");
  let jump = Input.keyPressed("Space") || Input.keyPressed("W") || Input.keyPressed("ArrowUp");

  if (moveL) { player.vx = -300; player.facing = -1; }
  else if (moveR) { player.vx = 300; player.facing = 1; }
  else player.vx *= 0.82;

  if (jump && player.jumps < 2) { player.vy = -440; player.jumps++; player.grounded = false; }

  player.vy += 980 * dt;
  player.x += player.vx * dt;
  player.y += player.vy * dt;

  player.grounded = false;
  for (let i = 0; i < platforms.length; i++) {
    let p = platforms[i];
    if (player.x + player.w > p.x && player.x < p.x + p.w &&
        player.y + player.h > p.y && player.y + player.h < p.y + p.h + player.vy * dt + 5 && player.vy >= 0) {
      player.y = p.y - player.h; player.vy = 0; player.grounded = true; player.jumps = 0;
      if (p.isGoal) winTimer = 2;
    }
  }
  if (player.y > 1000) { lives--; deathTimer = 1; }

  for (let i = 0; i < coins.length; i++) {
    let c = coins[i];
    if (!c.collected && Math.abs(player.x + player.w / 2 - c.x - 8) < 24 && Math.abs(player.y + player.h / 2 - c.y - 8) < 24) {
      c.collected = true; score += 10;
    }
  }

  for (let i = 0; i < enemies.length; i++) {
    let e = enemies[i];
    if (!e.alive) continue;
    e.x += e.vx * dt;
    if (e.x <= e.minX || e.x >= e.maxX) e.vx = -e.vx;
    if (Math.abs(player.x + player.w / 2 - e.x - e.w / 2) < 28 && Math.abs(player.y + player.h / 2 - e.y - e.h / 2) < 28) {
      if (player.vy > 0 && player.y + player.h < e.y + e.h / 2) { e.alive = false; player.vy = -300; score += 25; }
      else { lives--; deathTimer = 1; }
    }
  }

  cam.x += (player.x - W / 3 - cam.x) * 5 * dt;
  if (Input.keyPressed("Escape")) state = "paused";
}

function drawPlatformer() {
  let ox = -cam.x;

  // Sky
  R(0, 0, W, H * 0.55, 0.06, 0.07, 0.14, 1);
  R(0, H * 0.55, W, H * 0.45, 0.03, 0.04, 0.08, 1);

  // Stars
  for (let i = 0; i < 40; i++) {
    let sx = ((i * 137 + 50) % W + ox * 0.03) % W;
    let sy = (i * 97 + 30) % (H * 0.5);
    R(sx, sy, 2, 2, 1, 1, 1, 0.25 + Math.sin(gt * 1.5 + i) * 0.2);
  }

  // Platforms
  for (let i = 0; i < platforms.length; i++) {
    let p = platforms[i], dx = p.x + ox;
    if (dx + p.w < -50 || dx > W + 50) continue;
    if (p.isGoal) {
      box(dx, p.y, p.w, p.h, C.accent, 0.9);
      R(dx, p.y, p.w, 2, C.accentH[0], C.accentH[1], C.accentH[2], 0.5);
      lblC("GOAL", 1.4, dx, p.w, p.y + p.h / 2 - 35, C.white, 0.95);
    } else {
      box(dx, p.y, p.w, p.h, p.c, 0.92);
      R(dx, p.y, p.w, 2, C.white[0], C.white[1], C.white[2], 0.08);
    }
  }

  // Coins
  for (let i = 0; i < coins.length; i++) {
    let c = coins[i];
    if (c.collected) continue;
    let cx = c.x + ox, cy = c.y + Math.sin(gt * 3 + i) * 5;
    if (cx < -20 || cx > W + 20) continue;
    R(cx, cy, 16, 16, C.accent[0], C.accent[1], C.accent[2], 0.95);
    R(cx + 2, cy + 2, 12, 2, C.accentH[0], C.accentH[1], C.accentH[2], 0.5);
  }

  // Enemies
  for (let i = 0; i < enemies.length; i++) {
    let e = enemies[i];
    if (!e.alive) continue;
    let ex = e.x + ox;
    if (ex < -30 || ex > W + 30) continue;
    R(ex, e.y, e.w, e.h, C.red[0], C.red[1], C.red[2], 0.95);
    R(ex + 4, e.y + 5, 5, 5, 1, 1, 1, 0.95);
    R(ex + e.w - 9, e.y + 5, 5, 5, 1, 1, 1, 0.95);
    R(ex + 6, e.y + 7, 2, 2, 0, 0, 0, 1);
    R(ex + e.w - 7, e.y + 7, 2, 2, 0, 0, 0, 1);
  }

  // Player
  if (deathTimer <= 0 && gameOverTimer <= 0) {
    let px = player.x + ox, py = player.y;
    R(px, py, player.w, player.h, C.cyan[0], C.cyan[1], C.cyan[2], 0.97);
    R(px + 1, py + 1, player.w - 2, 3, 1, 1, 1, 0.25);
    let eyeX = player.facing > 0 ? px + player.w - 14 : px + 4;
    R(eyeX, py + 10, 10, 8, 1, 1, 1, 0.97);
    R(player.facing > 0 ? eyeX + 5 : eyeX + 1, py + 12, 4, 4, 0.02, 0.02, 0.02, 1);
    if (Math.abs(player.vx) > 20 && player.grounded) {
      let lo = Math.sin(gt * 14) * 4;
      R(px + 4, py + player.h, 10, 6 + lo, C.cyan[0] * 0.6, C.cyan[1] * 0.6, C.cyan[2] * 0.6, 0.9);
      R(px + player.w - 14, py + player.h, 10, 6 - lo, C.cyan[0] * 0.6, C.cyan[1] * 0.6, C.cyan[2] * 0.6, 0.9);
    }
    if (!player.grounded) {
      R(px + player.w / 2 - 3, py + player.h, 6, 4, C.cyan[0] * 0.4, C.cyan[1] * 0.4, C.cyan[2] * 0.4, 0.5);
    }
  }

  // HUD
  box(0, 0, W, 48, C.bg, 0.92);
  R(0, 47, W, 1, C.border[0], C.border[1], C.border[2], 0.3);
  accentLine(0, 0, W);

  // Score
  R(14, 14, 16, 16, C.accent[0], C.accent[1], C.accent[2], 0.9);
  R(15, 15, 14, 2, C.accentH[0], C.accentH[1], C.accentH[2], 0.4);
  lbl(score.toString(), 38, 14, 1.5, C.accentH, 1);

  // Lives
  lbl("LIVES", 170, 8, 0.8, C.textDim, 0.5);
  for (let i = 0; i < lives; i++) {
    R(170 + i * 24, 22, 18, 18, C.green[0], C.green[1], C.green[2], 0.9);
    R(171 + i * 24, 23, 16, 2, C.white[0], C.white[1], C.white[2], 0.2);
  }

  // Level
  lblC("LEVEL " + level, 1.5, 0, W, 12, C.white, 0.85);

  // Jumps
  let jCol = player.jumps < 2 ? C.cyan : C.textOff;
  lbl("JUMP " + (2 - player.jumps) + "/2", W - 160, 14, 1.1, jCol, 0.8);

  lbl("ESC", W - 60, 14, 0.9, C.textOff, 0.4);

  // Overlays
  if (deathTimer > 0) {
    box(0, 0, W, H, C.red, 0.12 * deathTimer);
    lblCBig("OUCH!", 2.5, 0, W, H / 2 - 30, C.redH, clamp(deathTimer, 0, 1));
  }
  if (winTimer > 0) {
    box(0, 0, W, H, C.accent, 0.08 * winTimer);
    lblCBig("LEVEL COMPLETE!", 2.5, 0, W, H / 2 - 50, C.accentH, clamp(winTimer, 0, 1));
    lblC("Score: " + score, 1.8, 0, W, H / 2 + 15, C.white, clamp(winTimer, 0, 1) * 0.9);
  }
  if (gameOverTimer > 0) {
    box(0, 0, W, H, C.bg, 0.8);
    lblCBig("GAME OVER", 2.5, 0, W, H / 2 - 60, C.red, 1);
    lblC("Final Score: " + score, 2.0, 0, W, H / 2 + 10, C.accent, 0.95);
    lblC("Returning to menu...", 1.1, 0, W, H / 2 + 55, C.textDim, 0.5);
  }
}

function drawPaused() {
  drawPlatformer();
  box(0, 0, W, H, C.bg, 0.7);

  let pw = 400, ph = 320;
  let px = W / 2 - pw / 2, py = H / 2 - ph / 2;
  box(px, py, pw, ph, C.panel, 0.96);
  subtleBorder(px, py, pw, ph);
  accentLine(px, py, pw);

  lblCBig("PAUSED", 2.0, px, pw, py + 20, C.accent, 1);

  R(px + 50, py + 65, pw - 100, 1, C.border[0], C.border[1], C.border[2], 0.25);

  let by = py + 85;
  if (bigBtn(px + 30, by, pw - 60, 50, "RESUME", C.green, [0.25, 0.90, 0.45])) state = "playing";
  by += 62;
  if (menuBtn(px + 30, by, pw - 60, 46, "OPTIONS", C.blue)) state = "options";
  by += 58;
  if (menuBtn(px + 30, by, pw - 60, 46, "QUIT TO MENU", C.red)) state = "menu";
}

let bgBall;
function buildMenuBG() {
  let bg = new Cube({ width: 80, height: 80, depth: 1 });
  bg.position = new Vector3(0, 0, -15);
  bg.setMaterialColor(0.04, 0.04, 0.06);
  Scene.add(bg);

  bgBall = new Sphere({ radius: 3, segments: 20, rings: 14 });
  bgBall.position = new Vector3(2, 0, -6);
  bgBall.setMaterialColor(0.15, 0.14, 0.18);
  bgBall.setMaterialRoughness(0.15);
  bgBall.setMaterialMetallic(0.85);
  bgBall.setMaterialEmissive(C.accent[0] * 0.06, C.accent[1] * 0.06, C.accent[2] * 0.06);
  bgBall.setMaterialEmissiveStrength(3);
  Scene.add(bgBall);

  new PointLight({ x: -4, y: 3, z: -4, r: C.accent[0], g: C.accent[1], b: C.accent[2], intensity: 2.5, range: 18 });
  new PointLight({ x: 4, y: 2, z: -3, r: C.blue[0], g: C.blue[1], b: C.blue[2], intensity: 1.5, range: 14 });
  new PointLight({ x: 0, y: -2, z: -3, r: C.purple[0], g: C.purple[1], b: C.purple[2], intensity: 1, range: 10 });

  let p1 = Particles.createEmitter({ maxParticles: 60 });
  Particles.setPosition(p1, new Vector3(2, -3, -5));
  Particles.setDirection(p1, new Vector3(0, 1, 0));
  Particles.setSizes(p1, 0.03, 0.006);
  Particles.setSpeed(p1, 0.04, 0.2);
  Particles.setLifetime(p1, 3, 9);
  Particles.setGravity(p1, new Vector3(0.006, 0.012, 0));
  Particles.setRate(p1, 3);
  Particles.setSpread(p1, 4);
  Particles.setColors(p1, new Vector3(C.accentD[0], C.accentD[1], C.accentD[2]), new Vector3(C.accent[0], C.accent[1], C.accent[2]));

  Configuration.setAmbientColor(0.03, 0.03, 0.04);
  Configuration.setSkyboxTopColor(0.01, 0.01, 0.025);
  Configuration.setSkyboxBottomColor(0.03, 0.03, 0.04);
}

export function onStart() {
  try {
    buildMenuBG();
    try {
      fontId = GUI.loadFont("./examples/raw/assets/fonts/tahoma.ttf", 16);
      fontBigId = GUI.loadFont("./examples/raw/assets/fonts/tahoma.ttf", 48);
      Debug.log("Fonts loaded: body=" + fontId + " title=" + fontBigId);
    }
    catch (e) { Debug.log("Font fallback: " + e); fontId = 0; fontBigId = 0; }
    Window.fullscreen();
  } catch (e) { Debug.log("onStart: " + e); }
}

export function onUpdate(dt) {
  gt += dt;
  updateMouse();
  if (bgBall && (state === "menu" || state === "options" || state === "controls")) bgBall.rotate(0, dt * 8, 0);
  if (state === "menu") drawMenu();
  else if (state === "options") drawOptions();
  else if (state === "controls") drawControls();
  else if (state === "playing") { updatePlatformer(dt); drawPlatformer(); }
  else if (state === "paused") drawPaused();
}

function App() {
  return (<Box orientation="vertical" expand={true}><Canvas id="viewport" expand={true} /></Box>);
}

Stigma.onReady(function () { Stigma.render("root", App); });