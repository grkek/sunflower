import Stigma, { Window } from "stigma";
import {
  Scene,
  Cube,
  Sphere,
  Vector3,
  Input,
  GUI,
  Configuration,
  Debug,
  PointLight,
  Particles,
  Audio,
} from "tachyon";

//  UTILITIES

function rgb(r, g, b) {
  return { r, g, b };
}
function hex(s) {
  let c = s.replace("#", "");
  return {
    r: parseInt(c.substring(0, 2), 16) / 255,
    g: parseInt(c.substring(2, 4), 16) / 255,
    b: parseInt(c.substring(4, 6), 16) / 255,
  };
}
function lerp(a, b, t) {
  return a + (b - a) * t;
}
function lerpC(a, b, t) {
  return { r: lerp(a.r, b.r, t), g: lerp(a.g, b.g, t), b: lerp(a.b, b.b, t) };
}
function bright(c, n) {
  return { r: Math.min(1, c.r + n), g: Math.min(1, c.g + n), b: Math.min(1, c.b + n) };
}
function dark(c, n) {
  return { r: Math.max(0, c.r - n), g: Math.max(0, c.g - n), b: Math.max(0, c.b - n) };
}

const W = 1920,
  H = 1080;
const NUM_T = 8,
  NUM_S = 16,
  NUM_P = 4;

const T_HEX = [
  "#CC4444",
  "#CC8833",
  "#CCAA22",
  "#33AA66",
  "#3399CC",
  "#5544AA",
  "#9933AA",
  "#CC3388",
];
const T_COL = T_HEX.map((h) => hex(h));
const T_NAME = ["KICK", "SNARE", "HIHAT", "CLAP", "PERC", "BASS", "PIANO", "FLUTE"];
const P_NAME = ["A", "B", "C", "D"];
const P_COL = [hex("#CC6633"), hex("#3388BB"), hex("#33AA55"), hex("#BBAA33")];
const AUDIO_FILES = [
  "./examples/daw/assets/audio/kick.wav",
  "./examples/daw/assets/audio/snare.wav",
  "./examples/daw/assets/audio/hihat.wav",
  "./examples/daw/assets/audio/clap.wav",
  "./examples/daw/assets/audio/perc.wav",
  "./examples/daw/assets/audio/bass_c.wav",
  "./examples/daw/assets/audio/piano_c.wav",
  "./examples/daw/assets/audio/flute_c.wav",
];

const V = {
  // Panel backgrounds — that signature olive/khaki gray
  bg: rgb(0.29, 0.282, 0.251), // main panel fill
  bgDark: rgb(0.2, 0.196, 0.173), // darker areas, inset backgrounds
  bgDarker: rgb(0.145, 0.141, 0.125), // deepest inset / text field bg
  bgLight: rgb(0.345, 0.337, 0.302), // lighter panel / toolbar
  bgHover: rgb(0.38, 0.37, 0.33), // hover state

  // Bevels
  bevelLight: rgb(0.42, 0.412, 0.373), // top/left edge (raised)
  bevelDark: rgb(0.165, 0.161, 0.141), // bottom/right edge (raised)
  bevelInLight: rgb(0.165, 0.161, 0.141), // top/left edge (sunken/inset)
  bevelInDark: rgb(0.42, 0.412, 0.373), // bottom/right edge (sunken/inset)

  // Text
  text: rgb(0.878, 0.863, 0.784), // primary text — warm off-white
  textDim: rgb(0.545, 0.533, 0.482), // secondary/disabled text
  textBright: rgb(1.0, 0.98, 0.9), // highlighted text
  textDark: rgb(0.22, 0.216, 0.196), // text on bright backgrounds

  // Accent — amber/orange, the HL2 selection color
  accent: rgb(0.89, 0.6, 0.18), // primary selection/highlight
  accentDim: rgb(0.5, 0.34, 0.1), // dimmed accent
  accentBg: rgb(0.35, 0.25, 0.1), // accent background tint

  // Status colors (muted, not neon)
  green: rgb(0.38, 0.62, 0.28),
  greenDim: rgb(0.2, 0.33, 0.15),
  greenBg: rgb(0.16, 0.24, 0.12),
  red: rgb(0.72, 0.22, 0.18),
  redDim: rgb(0.4, 0.13, 0.1),
  yellow: rgb(0.78, 0.7, 0.22),
  yellowDim: rgb(0.4, 0.36, 0.11),

  // VU — slightly desaturated compared to modern DAW
  vuG: rgb(0.25, 0.65, 0.25),
  vuY: rgb(0.7, 0.64, 0.18),
  vuR: rgb(0.75, 0.2, 0.15),

  // Scrollbar / divider
  divider: rgb(0.18, 0.176, 0.157),
};

//  MOUSE STATE

let mx = 0,
  my = 0,
  mDown = false,
  mWasDown = false,
  mPressed = false;
function updateMouse() {
  let p = Input.mousePosition();
  mx = p.x;
  my = p.y;
  mWasDown = mDown;
  mDown = Input.mouseButtonDown(0);
  mPressed = mDown && !mWasDown;
}
function inRect(x, y, w, h) {
  return mx >= x && mx <= x + w && my >= y && my <= y + h;
}

//  SMOOTH ANIMATION STATE

let smoothVU = new Array(NUM_T).fill(0);
let smoothPeaks = new Array(NUM_T).fill(0);
let peakHold = new Array(NUM_T).fill(0);
let padFlash = [];
for (let t = 0; t < NUM_T; t++) padFlash[t] = new Array(NUM_S).fill(0);
let playheadGlow = 0;

function R(x, y, w, h, c, a) {
  GUI.rect(x, y, w, h, c.r, c.g, c.b, a !== undefined ? a : 1);
}
function TX(s, x, y, sc, c, a) {
  GUI.text(s, x, y, sc, c.r, c.g, c.b, a !== undefined ? a : 1);
}

function bevelRaised(x, y, w, h) {
  // Top edge — light
  R(x, y, w, 1, V.bevelLight);
  R(x, y + 1, w - 1, 1, V.bevelLight, 0.5);
  // Left edge — light
  R(x, y, 1, h, V.bevelLight);
  R(x + 1, y, 1, h - 1, V.bevelLight, 0.5);
  // Bottom edge — dark
  R(x, y + h - 1, w, 1, V.bevelDark);
  R(x + 1, y + h - 2, w - 1, 1, V.bevelDark, 0.5);
  // Right edge — dark
  R(x + w - 1, y, 1, h, V.bevelDark);
  R(x + w - 2, y + 1, 1, h - 1, V.bevelDark, 0.5);
}

function bevelSunken(x, y, w, h) {
  R(x, y, w, 1, V.bevelInLight);
  R(x, y + 1, w - 1, 1, V.bevelInLight, 0.5);
  R(x, y, 1, h, V.bevelInLight);
  R(x + 1, y, 1, h - 1, V.bevelInLight, 0.5);
  R(x, y + h - 1, w, 1, V.bevelInDark);
  R(x + 1, y + h - 2, w - 1, 1, V.bevelInDark, 0.5);
  R(x + w - 1, y, 1, h, V.bevelInDark);
  R(x + w - 2, y + 1, 1, h - 1, V.bevelInDark, 0.5);
}

function vPanel(x, y, w, h, bg) {
  R(x, y, w, h, bg || V.bg);
  bevelRaised(x, y, w, h);
}

function vInset(x, y, w, h, bg) {
  R(x, y, w, h, bg || V.bgDarker);
  bevelSunken(x, y, w, h);
}

function vDivider(x, y, h) {
  R(x, y, 1, h, V.bevelDark);
  R(x + 1, y, 1, h, V.bevelLight, 0.5);
}

function vDividerH(x, y, w) {
  R(x, y, w, 1, V.bevelDark);
  R(x, y + 1, w, 1, V.bevelLight, 0.5);
}
//  raised bevel when normal, flat/sunken when pressed,
//  amber highlight when active. Text shifts 1px down-right on press.

function vBtn(x, y, w, h, label, active, accentCol) {
  let hov = inRect(x, y, w, h);
  let pressing = hov && mDown;
  let clicked = hov && mPressed;

  if (active) {
    R(x, y, w, h, accentCol || V.accent);
    bevelRaised(x, y, w, h);
    if (label) {
      let sc = h > 26 ? 1.3 : 1.0;
      let cw = sc * 7.5;
      let tx = x + (w - label.length * cw) / 2;
      let ty = y + (h - sc * 8) / 2;
      TX(label, tx, ty, sc, V.textDark);
    }
  } else if (pressing) {
    R(x, y, w, h, V.bgDark);
    bevelSunken(x, y, w, h);
    if (label) {
      let sc = h > 26 ? 1.3 : 1.0;
      let cw = sc * 7.5;
      let tx = x + (w - label.length * cw) / 2 + 1;
      let ty = y + (h - sc * 8) / 2 + 1;
      TX(label, tx, ty, sc, V.textDim);
    }
  } else {
    R(x, y, w, h, hov ? V.bgHover : V.bgLight);
    bevelRaised(x, y, w, h);
    if (label) {
      let sc = h > 26 ? 1.3 : 1.0;
      let cw = sc * 7.5;
      let tx = x + (w - label.length * cw) / 2;
      let ty = y + (h - sc * 8) / 2;
      TX(label, tx, ty, sc, hov ? V.textBright : V.text);
    }
  }

  return clicked;
}

function vToggle(x, y, w, h, label, on, onCol) {
  let hov = inRect(x, y, w, h);
  let clicked = hov && mPressed;

  if (on) {
    R(x, y, w, h, onCol || V.green);
    bevelSunken(x, y, w, h);
  } else {
    R(x, y, w, h, hov ? bright(V.bgDark, 0.03) : V.bgDark);
    bevelRaised(x, y, w, h);
  }

  if (label) {
    let sc = h > 20 ? 1.1 : 0.9;
    let cw = sc * 7.5;
    let tx = x + (w - label.length * cw) / 2;
    let ty = y + (h - sc * 8) / 2;
    TX(label, tx, ty, sc, on ? V.textBright : V.textDim);
  }
  return clicked;
}

function vFader(x, y, w, h, val, color) {
  vInset(x, y, w, h);

  let fillH = h * Math.max(0, Math.min(1, val));
  if (fillH > 1) {
    R(x + 2, y + h - fillH, w - 4, fillH, dark(color, 0.1), 0.55);
  }

  // Knob — raised
  let ky = y + h - fillH;
  R(x, ky - 3, w, 7, V.bgLight);
  bevelRaised(x, ky - 3, w, 7);

  // Center notch
  R(x + 2, y + Math.floor(h / 2), w - 4, 1, V.divider, 0.4);

  let hov = inRect(x - 6, y, w + 12, h);
  if (hov && mDown) {
    val = 1 - (my - y) / h;
    val = Math.max(0, Math.min(1, val));
  }
  return val;
}

function vHFader(x, y, w, h, val, color) {
  vInset(x, y, w, h);

  let fillW = w * Math.max(0, Math.min(1, val));
  if (fillW > 0) {
    R(x + 2, y + 2, fillW - 2, h - 4, dark(color, 0.05), 0.45);
  }

  let kx = x + fillW;
  R(kx - 3, y, 7, h, V.bgLight);
  bevelRaised(kx - 3, y, 7, h);

  let hov = inRect(x, y - 4, w, h + 8);
  if (hov && mDown) {
    val = (mx - x) / w;
    val = Math.max(0, Math.min(1, val));
  }
  return val;
}

function vVU(x, y, w, h, level, peak) {
  vInset(x, y, w, h);

  let bH = h * Math.max(0, Math.min(1, level));
  if (bH > 0) {
    let gZ = h * 0.6,
      yZ = h * 0.25;
    let gH = Math.min(bH, gZ);
    let yH = Math.min(Math.max(0, bH - gZ), yZ);
    let rH = Math.max(0, bH - gZ - yZ);

    if (gH > 0) R(x + 2, y + h - gH - 2, w - 4, gH, V.vuG, 0.85);
    if (yH > 0) R(x + 2, y + h - gZ - yH - 2, w - 4, yH, V.vuY, 0.85);
    if (rH > 0) R(x + 2, y + h - gZ - yZ - rH - 2, w - 4, rH, V.vuR, 0.85);

    // Segment gaps
    for (let s = 4; s < h - 4; s += 4) {
      R(x + 2, y + s, w - 4, 1, V.bgDarker, 0.35);
    }
  }

  if (peak > 0.01) {
    let py = y + h - h * Math.min(1, peak) - 2;
    let pc = peak > 0.85 ? V.vuR : peak > 0.6 ? V.vuY : V.vuG;
    R(x + 2, py, w - 4, 2, pc, 0.8);
  }
}

function vStepPad(x, y, w, h, active, isPlayCol, color, flash) {
  let hov = inRect(x, y, w, h);
  let clicked = hov && mPressed;

  if (active) {
    let c = isPlayCol ? bright(color, 0.12 + flash * 0.15) : color;
    R(x, y, w, h, c);
    // Sunken bevel for active pads (they look "pressed in")
    bevelSunken(x, y, w, h);
    // Flash glow
    if (flash > 0.05) {
      R(x, y, w, h, V.textBright, flash * 0.12);
    }
  } else if (isPlayCol) {
    R(x, y, w, h, bright(V.bgDark, 0.04));
    bevelSunken(x, y, w, h);
  } else {
    R(x, y, w, h, hov ? bright(V.bgDarker, 0.03) : V.bgDarker);
    bevelSunken(x, y, w, h);
  }

  return clicked;
}

function vLabel(x, y, text, sc, col) {
  TX(text, x, y, sc || 1.2, col || V.text);
}

function vDisplay(x, y, w, h, text, textCol) {
  vInset(x, y, w, h);
  let sc = h > 22 ? 1.5 : 1.1;
  let cw = sc * 7.5;
  TX(text, x + (w - text.length * cw) / 2, y + (h - sc * 8) / 2, sc, textCol || V.textBright);
}

//  DAW STATE

let bpm = 128,
  playing = false,
  curStep = 0,
  stepTimer = 0;
let patterns = [],
  curPat = 0;
for (let p = 0; p < NUM_P; p++) {
  patterns[p] = [];
  for (let t = 0; t < NUM_T; t++) patterns[p][t] = new Array(NUM_S).fill(false);
}
let grid = patterns[0];
let tVol = [0.9, 0.8, 0.75, 0.7, 0.65, 0.85, 0.8, 0.7];
let tPan = [0, 0, 0.15, -0.1, 0.2, 0, -0.15, 0.1];
let tMute = new Array(NUM_T).fill(false);
let tSolo = new Array(NUM_T).fill(false);
let hasSolo = false;
let masterVol = 0.85;
let rawVU = new Array(NUM_T).fill(0);
let view = "channel";
let gt = 0;

//  DEFAULT PATTERNS

function initPatterns() {
  let a = patterns[0];
  [0, 4, 8, 12].forEach((s) => (a[0][s] = true));
  a[1][4] = a[1][12] = true;
  [0, 2, 4, 6, 8, 10, 12, 14].forEach((s) => (a[2][s] = true));
  a[3][2] = a[3][10] = true;
  a[4][3] = a[4][7] = a[4][11] = true;
  a[5][0] = a[5][6] = a[5][8] = true;
  a[6][0] = a[6][4] = a[6][8] = a[6][14] = true;
  a[7][6] = a[7][14] = true;

  let b = patterns[1];
  b[0][0] = b[0][5] = b[0][10] = true;
  b[1][4] = b[1][11] = b[1][14] = true;
  [0, 2, 4, 6, 8, 10, 12, 14].forEach((s) => (b[2][s] = true));
  b[3][4] = b[3][12] = true;
  b[4][2] = b[4][6] = b[4][9] = true;
  b[5][0] = b[5][5] = b[5][10] = true;
  b[6][0] = b[6][6] = b[6][12] = true;
  b[7][3] = b[7][11] = true;

  let c = patterns[2];
  c[0][0] = c[0][8] = true;
  c[1][8] = true;
  [0, 2, 4, 6, 8, 10, 11, 12, 13, 14, 15].forEach((s) => (c[2][s] = true));
  c[3][4] = c[3][12] = true;
  [0, 4, 8, 12].forEach((s) => (c[5][s] = true));
  c[6][0] = c[6][8] = true;
  c[7][7] = c[7][15] = true;

  grid = patterns[curPat];
}

//  AUDIO — Polyphony pool + fire-and-forget

const POOL = 8;
let pool = [],
  poolIdx = [];

function loadAudio() {
  for (let t = 0; t < NUM_T; t++) {
    pool[t] = [];
    poolIdx[t] = 0;
    for (let v = 0; v < POOL; v++) {
      try {
        let h = Audio.load(AUDIO_FILES[t]);
        if (h) {
          Audio.setLooping(h, false);
          Audio.setVolume(h, 0);
          pool[t].push(h);
        }
      } catch (e) {
        Debug.log("Audio " + t + "/" + v + ": " + e);
      }
    }
  }
}

function triggerTrack(t) {
  if (tMute[t]) return;
  if (hasSolo && !tSolo[t]) return;
  if (pool[t] && pool[t].length > 0) {
    let idx = poolIdx[t] % pool[t].length;
    let h = pool[t][idx];
    poolIdx[t]++;
    Audio.stop(h);
    Audio.setVolume(h, tVol[t] * masterVol);
    Audio.start(h);
  }
  try {
    Audio.play(AUDIO_FILES[t]);
  } catch (e) {}
  rawVU[t] = 1;
}

function recalcSolo() {
  hasSolo = false;
  for (let t = 0; t < NUM_T; t++)
    if (tSolo[t]) {
      hasSolo = true;
      break;
    }
}

//  SEQUENCER

function tick() {
  for (let t = 0; t < NUM_T; t++) {
    if (grid[t][curStep]) {
      triggerTrack(t);
      padFlash[t][curStep] = 1;
    }
  }
  playheadGlow = 1;
  curStep = (curStep + 1) % NUM_S;
}

//  BACKGROUND

let discoBall, bgP1, bgP2;

function buildBG() {
  let bg = new Cube({ width: 100, height: 100, depth: 1 });
  bg.position = new Vector3(0, 0, -20);
  bg.setMaterialColor(0.08, 0.07, 0.06);
  Scene.add(bg);

  discoBall = new Sphere({ radius: 1.8, segments: 20, rings: 14 });
  discoBall.position = new Vector3(0, 2.5, -10);
  discoBall.setMaterialColor(0.55, 0.52, 0.48);
  discoBall.setMaterialRoughness(0.08);
  discoBall.setMaterialMetallic(0.9);
  discoBall.setMaterialEmissive(0.1, 0.08, 0.06);
  discoBall.setMaterialEmissiveStrength(1.5);
  Scene.add(discoBall);

  new PointLight({ x: -4, y: 4, z: -5, r: 0.9, g: 0.6, b: 0.2, intensity: 2.5, range: 18 });
  new PointLight({ x: 4, y: 4, z: -5, r: 0.4, g: 0.3, b: 0.15, intensity: 2, range: 16 });
  new PointLight({ x: 0, y: -1, z: -5, r: 0.3, g: 0.25, b: 0.15, intensity: 1.5, range: 12 });

  bgP1 = Particles.createEmitter({ maxParticles: 80 });
  Particles.setPosition(bgP1, new Vector3(0, -1, -8));
  Particles.setDirection(bgP1, new Vector3(0, 1, 0));
  Particles.setSizes(bgP1, 0.04, 0.01);
  Particles.setSpeed(bgP1, 0.06, 0.3);
  Particles.setLifetime(bgP1, 4, 10);
  Particles.setGravity(bgP1, new Vector3(0.01, 0.02, 0));
  Particles.setRate(bgP1, 3);
  Particles.setSpread(bgP1, 5);
  Particles.setColors(bgP1, new Vector3(0.5, 0.4, 0.2), new Vector3(0.8, 0.5, 0.2));

  bgP2 = Particles.createEmitter({ maxParticles: 40 });
  Particles.setPosition(bgP2, new Vector3(0, 6, -8));
  Particles.setDirection(bgP2, new Vector3(0, -1, 0));
  Particles.setSizes(bgP2, 0.03, 0.01);
  Particles.setSpeed(bgP2, 0.1, 0.4);
  Particles.setLifetime(bgP2, 2, 6);
  Particles.setGravity(bgP2, new Vector3(0, -0.06, 0));
  Particles.setRate(bgP2, 2);
  Particles.setSpread(bgP2, 5);
  Particles.setColors(bgP2, new Vector3(0.6, 0.45, 0.2), new Vector3(0.4, 0.3, 0.15));

  Configuration.setAmbientColor(0.06, 0.05, 0.04);
  Configuration.setSkyboxTopColor(0.04, 0.035, 0.03);
  Configuration.setSkyboxBottomColor(0.06, 0.05, 0.04);
}

function updateBG(dt) {
  if (!discoBall) return;
  discoBall.rotate(0, dt * 10, 0);
  if (playing) {
    let pulse = rawVU[0] * 0.2;
    discoBall.setMaterialEmissive(0.1 + pulse, 0.08 + pulse * 0.6, 0.06 + pulse * 0.3);
    discoBall.setMaterialEmissiveStrength(1.5 + pulse * 4);
  }
  if (playing && curStep % 4 === 0 && rawVU[0] > 0.7) {
    Particles.emitBurst(bgP1, 6);
    Particles.emitBurst(bgP2, 4);
  }
}

//  TRANSPORT BAR

function drawTransport() {
  let bH = 52;

  // Main toolbar panel
  vPanel(0, 0, W, bH, V.bgLight);

  // Accent stripe at very top
  R(0, 0, W, 2, V.accent);

  let cx = 10;

  // Title
  TX("TACHYON DAW", cx, 14, 1.8, V.accent);
  cx += 165;

  vDivider(cx, 8, bH - 16);
  cx += 10;

  // Play
  if (vBtn(cx, 10, 60, 32, playing ? "PAUSE" : "PLAY", playing, V.green)) {
    playing = !playing;
    if (playing) {
      curStep = 0;
      stepTimer = 0;
    }
  }
  cx += 66;

  // Stop
  if (vBtn(cx, 10, 52, 32, "STOP", false, V.red)) {
    playing = false;
    curStep = 0;
    stepTimer = 0;
  }
  cx += 58;

  vDivider(cx, 8, bH - 16);
  cx += 10;

  // BPM
  TX("BPM", cx, 16, 1.0, V.textDim);
  vDisplay(cx + 32, 10, 58, 24, bpm.toString(), V.accent);
  if (vBtn(cx + 95, 10, 22, 24, "+", false)) bpm = Math.min(300, bpm + 1);
  if (vBtn(cx + 120, 10, 22, 24, "-", false)) bpm = Math.max(40, bpm - 1);
  cx += 152;

  vDivider(cx, 8, bH - 16);
  cx += 10;

  // Step
  TX("STEP", cx, 16, 1.0, V.textDim);
  vDisplay(cx + 38, 10, 50, 24, curStep + 1 + "/16", playing ? V.green : V.textDim);
  cx += 100;

  vDivider(cx, 8, bH - 16);
  cx += 10;

  // Pattern
  TX("PAT", cx, 16, 1.0, V.textDim);
  cx += 28;
  for (let p = 0; p < NUM_P; p++) {
    if (vBtn(cx + p * 36, 10, 30, 24, P_NAME[p], p === curPat, V.accent)) {
      curPat = p;
      grid = patterns[curPat];
    }
  }
  cx += 155;

  vDivider(cx, 8, bH - 16);
  cx += 10;

  // View
  if (vBtn(cx, 10, 82, 24, "CHANNEL", view === "channel", V.accent)) view = "channel";
  if (vBtn(cx + 88, 10, 62, 24, "MIXER", view === "mixer", V.accent)) view = "mixer";
  cx += 164;

  vDivider(cx, 8, bH - 16);
  cx += 10;

  // Master
  TX("MASTER", cx, 16, 0.9, V.textDim);
  masterVol = vHFader(cx + 56, 14, 110, 14, masterVol, V.accent);
  TX(Math.round(masterVol * 100) + "%", cx + 172, 14, 1.0, V.text);

  // Clock
  let sec = Math.floor(gt);
  let mm = Math.floor(sec / 60),
    ss = sec % 60;
  TX((mm < 10 ? "0" : "") + mm + ":" + (ss < 10 ? "0" : "") + ss, W - 100, 15, 1.5, V.textDim);

  // Bottom bevel
  vDividerH(0, bH - 2, W);
}

//  CHANNEL RACK

function drawChannelRack() {
  let top = 54,
    avH = H - top;

  // Left panel
  let lW = 220;
  vPanel(0, top, lW, avH, V.bg);

  // Header
  R(2, top + 2, lW - 4, 26, V.bgDark);
  bevelSunken(2, top + 2, lW - 4, 26);
  TX("CHANNEL RACK", 8, top + 7, 1.2, V.accent);
  TX("PAT " + P_NAME[curPat], lW - 55, top + 8, 1.0, P_COL[curPat]);

  let rowH = (avH - 30) / NUM_T;
  for (let t = 0; t < NUM_T; t++) {
    let ry = top + 30 + t * rowH;
    let c = T_COL[t];
    let even = t % 2 === 0;

    R(2, ry, lW - 4, rowH, even ? V.bg : dark(V.bg, 0.01));

    // Color bar
    R(2, ry, 5, rowH, c, 0.75);

    // Track name
    TX(T_NAME[t], 12, ry + rowH / 2 - 6, 1.2, c, 0.85);

    // Volume
    tVol[t] = vHFader(86, ry + rowH / 2 - 5, 52, 10, tVol[t], c);

    // Mute
    if (vToggle(146, ry + rowH / 2 - 8, 24, 16, "M", tMute[t], V.red)) tMute[t] = !tMute[t];

    // Solo
    if (vToggle(174, ry + rowH / 2 - 8, 24, 16, "S", tSolo[t], V.yellow)) {
      tSolo[t] = !tSolo[t];
      recalcSolo();
    }

    // Mini VU
    let lv = smoothVU[t] * tVol[t] * masterVol;
    if (tMute[t]) lv = 0;
    if (hasSolo && !tSolo[t]) lv = 0;
    R(lW - 10, ry + 3, 5, rowH - 6, V.bgDarker);
    let vuF = (rowH - 6) * lv;
    if (vuF > 0) R(lW - 10, ry + 3 + rowH - 6 - vuF, 5, vuF, c, 0.65);

    // Row divider
    vDividerH(2, ry + rowH - 2, lW - 4);
  }

  // Right panel — step grid
  let gX = lW + 1,
    gW = W - lW - 1;
  vPanel(gX, top, gW, avH, V.bgDark);

  let padW = gW / NUM_S;

  // Step header
  R(gX + 2, top + 2, gW - 4, 26, V.bgDarker);
  bevelSunken(gX + 2, top + 2, gW - 4, 26);
  for (let s = 0; s < NUM_S; s++) {
    let px = gX + s * padW;
    let isBeat = s % 4 === 0;
    let isCur = s === curStep && playing;
    let num = (s + 1).toString();
    TX(
      num,
      px + padW / 2 - num.length * 4,
      top + 8,
      1.0,
      isCur ? V.accent : isBeat ? V.text : V.textDim,
      isCur ? 1 : 0.5,
    );
  }

  // Beat group dividers
  for (let s = 4; s < NUM_S; s += 4) {
    let px = gX + s * padW;
    R(px, top + 28, 2, avH - 28, V.divider, 0.4);
  }

  // Playhead
  if (playing) {
    let phX = gX + curStep * padW;
    R(phX, top + 28, padW, avH - 28, V.accent, 0.06 + playheadGlow * 0.04);
    R(phX, top + 26, padW, 2, V.accent, 0.6 + playheadGlow * 0.4);
  }

  // Step pads
  let pRowH = (avH - 30) / NUM_T;
  for (let t = 0; t < NUM_T; t++) {
    let ry = top + 30 + t * pRowH;
    let c = T_COL[t];

    for (let s = 0; s < NUM_S; s++) {
      let px = gX + s * padW;
      let mg = 2;
      let active = grid[t][s];
      let isPC = s === curStep && playing;
      let flash = padFlash[t][s];

      if (vStepPad(px + mg, ry + mg, padW - mg * 2, pRowH - mg * 2, active, isPC, c, flash)) {
        grid[t][s] = !grid[t][s];
        if (grid[t][s]) {
          triggerTrack(t);
          padFlash[t][s] = 1;
        }
      }
    }

    // Row divider
    R(gX, ry + pRowH - 1, gW, 1, V.divider, 0.2);
  }
}

//  MIXER VIEW

function drawMixerView() {
  let top = 54,
    avH = H - top;
  let totalCh = NUM_T + 1;
  let chW = Math.floor(W / totalCh);

  vPanel(0, top, W, avH, V.bgDark);

  // Header
  R(2, top + 2, W - 4, 26, V.bgDarker);
  bevelSunken(2, top + 2, W - 4, 26);
  TX("MIXER", 10, top + 7, 1.4, V.accent);
  TX("PAT " + P_NAME[curPat], 90, top + 8, 1.1, P_COL[curPat], 0.8);

  for (let t = 0; t < NUM_T; t++) {
    let cx = t * chW + 2;
    let cy = top + 30;
    let ch = avH - 32;
    let c = T_COL[t];
    let even = t % 2 === 0;

    vPanel(cx, cy, chW - 4, ch, even ? V.bg : dark(V.bg, 0.01));

    // Color header
    R(cx + 2, cy + 2, chW - 8, 3, c, 0.7);

    // Track info
    TX((t + 1).toString(), cx + 8, cy + 12, 1.6, c, 0.85);
    TX(T_NAME[t], cx + 8, cy + 30, 1.0, V.textDim);

    // VU
    let vuX = cx + 10,
      vuY = cy + 48;
    let vuW = 14,
      vuH = ch - 240;
    let lv = smoothVU[t] * tVol[t] * masterVol;
    if (tMute[t]) lv = 0;
    if (hasSolo && !tSolo[t]) lv = 0;
    vVU(vuX, vuY, vuW, vuH, lv, smoothPeaks[t] * tVol[t]);
    vVU(vuX + vuW + 2, vuY, vuW, vuH, lv * 0.88, smoothPeaks[t] * tVol[t] * 0.88);

    // Fader
    let fX = vuX + vuW * 2 + 10;
    let fW = chW - fX + cx - 10;
    if (fW < 14) fW = 14;
    tVol[t] = vFader(fX, vuY, fW, vuH, tVol[t], c);

    // Volume readout
    TX(Math.round(tVol[t] * 100) + "%", cx + 8, vuY + vuH + 8, 1.0, V.text, 0.6);

    // Pan
    let panY = vuY + vuH + 28;
    TX("PAN", cx + 6, panY, 0.85, V.textDim);
    vInset(cx + 32, panY, chW - 48, 10);
    let panCenter = cx + 32 + (chW - 48) / 2;
    let panPos = panCenter + (tPan[t] * (chW - 48)) / 2;
    R(panCenter - 1, panY + 1, 2, 8, V.divider, 0.4);
    R(panPos - 2, panY, 5, 10, V.accent);

    // Mute/Solo
    let bY = panY + 20;
    let bW = Math.floor((chW - 16) / 2);
    if (vToggle(cx + 4, bY, bW - 1, 24, "MUTE", tMute[t], V.red)) tMute[t] = !tMute[t];
    if (vToggle(cx + bW + 5, bY, bW - 1, 24, "SOLO", tSolo[t], V.yellow)) {
      tSolo[t] = !tSolo[t];
      recalcSolo();
    }

    // Send
    let snY = bY + 32;
    TX("SEND", cx + 6, snY, 0.8, V.textDim);
    vInset(cx + 38, snY + 1, chW - 52, 6);
    R(cx + 40, snY + 3, (chW - 56) * tVol[t] * 0.5, 2, V.accent, 0.5);

    // Channel divider
    if (t > 0) R(cx - 1, cy, 1, ch, V.divider, 0.4);
  }

  // Master
  let mcx = NUM_T * chW + 2;
  let mcy = top + 30,
    mch = avH - 32;
  vPanel(mcx, mcy, chW - 4, mch, V.bgLight);
  R(mcx + 2, mcy + 2, chW - 8, 3, V.textBright, 0.6);
  TX("MST", mcx + 8, mcy + 12, 1.8, V.textBright);
  TX("MASTER", mcx + 8, mcy + 32, 0.9, V.textDim);

  let mVuY = mcy + 48,
    mVuH = mch - 200;
  let mLv = 0;
  for (let t = 0; t < NUM_T; t++) {
    let l = smoothVU[t] * tVol[t];
    if (tMute[t]) l = 0;
    if (hasSolo && !tSolo[t]) l = 0;
    if (l > mLv) mLv = l;
  }
  mLv *= masterVol;
  vVU(mcx + 10, mVuY, 18, mVuH, mLv, mLv);
  vVU(mcx + 32, mVuY, 18, mVuH, mLv * 0.92, mLv * 0.92);
  masterVol = vFader(mcx + 58, mVuY, chW - 74, mVuH, masterVol, V.accent);
  TX(Math.round(masterVol * 100) + "%", mcx + 10, mVuY + mVuH + 10, 1.2, V.textBright, 0.8);
}

//  MAIN

export function onStart() {
  try {
    initPatterns();
    buildBG();
    loadAudio();
    Configuration.setShadowResolution(2048);
    Window.fullscreen();
  } catch (e) {
    Debug.log("onStart: " + e + ", " + e.stack);
  }
}

export function onUpdate(dt) {
  gt += dt;
  updateMouse();

  if (playing) {
    stepTimer += dt;
    let interval = 60.0 / bpm / 4;
    if (stepTimer >= interval) {
      stepTimer -= interval;
      tick();
    }
  }

  // Smooth VU
  for (let t = 0; t < NUM_T; t++) {
    if (rawVU[t] > 0) rawVU[t] = Math.max(0, rawVU[t] - dt * 4);
    if (rawVU[t] > smoothVU[t]) smoothVU[t] = rawVU[t];
    else smoothVU[t] = lerp(smoothVU[t], rawVU[t], 1 - Math.exp(-dt * 8));
    if (rawVU[t] > smoothPeaks[t]) {
      smoothPeaks[t] = rawVU[t];
      peakHold[t] = 1.2;
    }
    if (peakHold[t] > 0) peakHold[t] -= dt;
    else if (smoothPeaks[t] > 0) smoothPeaks[t] = lerp(smoothPeaks[t], 0, 1 - Math.exp(-dt * 2));
  }

  // Pad flash / playhead decay
  for (let t = 0; t < NUM_T; t++)
    for (let s = 0; s < NUM_S; s++)
      if (padFlash[t][s] > 0) padFlash[t][s] = Math.max(0, padFlash[t][s] - dt * 4);
  if (playheadGlow > 0) playheadGlow = Math.max(0, playheadGlow - dt * 6);

  updateBG(dt);

  if (Input.keyPressed("Space")) {
    playing = !playing;
    if (playing) {
      curStep = 0;
      stepTimer = 0;
    }
  }

  drawTransport();
  if (view === "channel") drawChannelRack();
  else drawMixerView();
}

function App() {
  return (
    <Box orientation="vertical" expand={true}>
      <Canvas id="viewport" expand={true} />
    </Box>
  );
}
Stigma.onReady(function () {
  Stigma.render("root", App);
});