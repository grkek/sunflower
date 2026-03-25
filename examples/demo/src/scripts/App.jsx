import Stigma, { Window } from "stigma";

import {
  Scene,
  Cube,
  Vector3,
  Input,
  GUI,
  Configuration,
  Pipeline,
  Debug,
  PointLight,
  Particles
} from "tachyon";

import FirstPersonController from "./Components/FirstPersonController.js";

let meshes = [];

function hex(str) {
  let c = str.replace("#", "");
  return {
    r: parseInt(c.substring(0, 2), 16) / 255,
    g: parseInt(c.substring(2, 4), 16) / 255,
    b: parseInt(c.substring(4, 6), 16) / 255,
  };
}

function addBlock(player, x, y, z, w, h, d, r, g, b, minH, opts) {
  let cube = new Cube({ width: w, height: h, depth: d });
  cube.position = new Vector3(x, y + h / 2, z);
  cube.setMaterialColor(r, g, b);
  if (opts) {
    if (opts.roughness !== undefined) cube.setMaterialRoughness(opts.roughness);
    if (opts.metallic !== undefined) cube.setMaterialMetallic(opts.metallic);
    if (opts.emissive) cube.setMaterialEmissive(opts.emissive[0], opts.emissive[1], opts.emissive[2]);
    if (opts.emissiveStrength) cube.setMaterialEmissiveStrength(opts.emissiveStrength);
  }
  Scene.add(cube);
  meshes.push(cube);
  player.addObstacle(x, z, w / 2, d / 2, y + h, minH || y);
  return cube;
}

function addBlockHex(player, x, y, z, w, h, d, color, minH, opts) {
  let c = hex(color);
  return addBlock(player, x, y, z, w, h, d, c.r, c.g, c.b, minH, opts);
}

function addDecoration(x, y, z, w, h, d, r, g, b, opts) {
  let cube = new Cube({ width: w, height: h, depth: d });
  cube.position = new Vector3(x, y + h / 2, z);
  cube.setMaterialColor(r, g, b);
  if (opts) {
    if (opts.roughness !== undefined) cube.setMaterialRoughness(opts.roughness);
    if (opts.metallic !== undefined) cube.setMaterialMetallic(opts.metallic);
    if (opts.emissive) cube.setMaterialEmissive(opts.emissive[0], opts.emissive[1], opts.emissive[2]);
    if (opts.emissiveStrength) cube.setMaterialEmissiveStrength(opts.emissiveStrength);
  }
  Scene.add(cube);
  meshes.push(cube);
  return cube;
}

function addDecoHex(x, y, z, w, h, d, color, opts) {
  let c = hex(color);
  return addDecoration(x, y, z, w, h, d, c.r, c.g, c.b, opts);
}

let emitters = {};

function createFireEmitter(x, y, z) {
  let e = Particles.createEmitter({ maxParticles: 128 });
  Particles.setPosition(e, new Vector3(x, y, z));
  Particles.setDirection(e, new Vector3(0, 1, 0));
  Particles.setSizes(e, 0.3, 0.05);
  Particles.setSpeed(e, 0.8, 2.0);
  Particles.setLifetime(e, 0.4, 1.2);
  Particles.setGravity(e, new Vector3(0, 0.5, 0));
  Particles.setRate(e, 25);
  Particles.setSpread(e, 0.3);
  Particles.setColors(e, new Vector3(1.0, 0.7, 0.1), new Vector3(1.0, 0.15, 0.0));
  return e;
}

function createEmberEmitter(x, y, z) {
  let e = Particles.createEmitter({ maxParticles: 64 });
  Particles.setPosition(e, new Vector3(x, y, z));
  Particles.setDirection(e, new Vector3(0, 1, 0));
  Particles.setSizes(e, 0.08, 0.02);
  Particles.setSpeed(e, 1.0, 3.0);
  Particles.setLifetime(e, 1.0, 3.0);
  Particles.setGravity(e, new Vector3(0, 0.3, 0));
  Particles.setRate(e, 8);
  Particles.setSpread(e, 0.6);
  Particles.setColors(e, new Vector3(1.0, 0.6, 0.1), new Vector3(1.0, 0.2, 0.0));
  return e;
}

function createDustEmitter(x, y, z) {
  let e = Particles.createEmitter({ maxParticles: 96 });
  Particles.setPosition(e, new Vector3(x, y, z));
  Particles.setDirection(e, new Vector3(0, 1, 0));
  Particles.setSizes(e, 0.15, 0.4);
  Particles.setSpeed(e, 0.05, 0.2);
  Particles.setLifetime(e, 4.0, 8.0);
  Particles.setGravity(e, new Vector3(0.02, 0.01, 0.01));
  Particles.setRate(e, 3);
  Particles.setSpread(e, 2.5);
  Particles.setColors(e, new Vector3(0.8, 0.75, 0.6), new Vector3(0.6, 0.55, 0.45));
  return e;
}

function createMysticEmitter(x, y, z) {
  let e = Particles.createEmitter({ maxParticles: 96 });
  Particles.setPosition(e, new Vector3(x, y, z));
  Particles.setDirection(e, new Vector3(0, 1, 0));
  Particles.setSizes(e, 0.12, 0.02);
  Particles.setSpeed(e, 0.2, 0.8);
  Particles.setLifetime(e, 2.0, 5.0);
  Particles.setGravity(e, new Vector3(0, 0.15, 0));
  Particles.setRate(e, 6);
  Particles.setSpread(e, 1.5);
  Particles.setColors(e, new Vector3(0.3, 0.7, 1.0), new Vector3(0.6, 0.2, 0.9));
  return e;
}

function createWaterfallMist(x, y, z) {
  let e = Particles.createEmitter({ maxParticles: 128 });
  Particles.setPosition(e, new Vector3(x, y, z));
  Particles.setDirection(e, new Vector3(0, 0, 1));
  Particles.setSizes(e, 0.5, 0.8);
  Particles.setSpeed(e, 0.1, 0.4);
  Particles.setLifetime(e, 3.0, 6.0);
  Particles.setGravity(e, new Vector3(0, 0.05, 0));
  Particles.setRate(e, 5);
  Particles.setSpread(e, 1.0);
  Particles.setColors(e, new Vector3(0.85, 0.9, 0.95), new Vector3(0.7, 0.8, 0.9));
  return e;
}

function buildScene(player) {
  let ground = new Cube({ width: 200, height: 0.1, depth: 200 });
  ground.position = new Vector3(0, 0, 0);
  ground.setMaterialColor(0.28, 0.22, 0.18);
  ground.setMaterialRoughness(0.95);
  Scene.add(ground);
  meshes.push(ground);

  for (let i = 0; i < 20; i++) {
    let gx = (Math.random() - 0.5) * 80;
    let gz = (Math.random() - 0.5) * 80;
    let gs = 2 + Math.random() * 5;
    let gd = 2 + Math.random() * 5;
    let green = 0.25 + Math.random() * 0.15;
    addDecoration(gx, 0.05, gz, gs, 0.02, gd, 0.2, green, 0.12, { roughness: 1.0 });
  }

  addBlockHex(player, 0, 0, 0, 14, 0.12, 14, "#5C5549");
  addBlockHex(player, 0, 0.12, 0, 2.4, 0.8, 2.4, "#6B6560", 0, { roughness: 0.9 });
  addDecoration(0, 0.85, 0, 1.8, 0.05, 1.8, 0.1, 0.15, 0.25, { roughness: 0.1, metallic: 0.3 });
  addBlockHex(player, -0.9, 0.92, -0.9, 0.15, 1.8, 0.15, "#5B3A1E");
  addBlockHex(player, 0.9, 0.92, -0.9, 0.15, 1.8, 0.15, "#5B3A1E");
  addBlockHex(player, 0, 2.72, -0.9, 2.2, 0.15, 0.15, "#5B3A1E");
  addBlockHex(player, 0, 2.87, -0.9, 2.6, 0.08, 1.2, "#8B4513");

  let tx = -8, tz = -4;
  addBlockHex(player, tx, 0, tz, 8, 0.2, 6, "#4A4540");
  addBlockHex(player, tx, 0.2, tz - 2.8, 8, 3.5, 0.4, "#8B7355");
  addBlockHex(player, tx, 0.2, tz + 2.8, 8, 3.5, 0.4, "#8B7355");
  addBlockHex(player, tx - 3.8, 0.2, tz, 0.4, 3.5, 6, "#8B7355");
  addBlockHex(player, tx + 3.8, 0.2, tz, 0.4, 3.5, 6, "#8B7355");
  addBlockHex(player, tx + 3.8, 2.5, tz, 0.5, 1.2, 1.5, "#8B7355", 2.5);
  addBlockHex(player, tx, 3.7, tz, 9, 0.2, 7, "#6B3320");
  addBlockHex(player, tx, 3.9, tz, 7, 0.15, 5, "#6B3320");
  addBlockHex(player, tx - 2.5, 3.9, tz - 1.5, 1.0, 2.0, 1.0, "#5A5550");
  addDecoHex(tx + 4.2, 2.8, tz, 0.1, 0.6, 1.2, "#C8A850", { emissive: [0.8, 0.6, 0.1], emissiveStrength: 2.0 });
  addBlockHex(player, tx - 1, 0.2, tz - 0.5, 1.2, 0.7, 0.8, "#5B3A1E");
  addBlockHex(player, tx + 1.5, 0.2, tz + 0.5, 1.0, 0.7, 1.0, "#5B3A1E");
  addBlockHex(player, tx - 2.5, 0.2, tz, 1.0, 1.0, 4.0, "#4A2A0E");
  emitters.tavernFire = createFireEmitter(tx - 2.5, 4.2, tz - 1.5);
  emitters.tavernEmbers = createEmberEmitter(tx - 2.5, 4.8, tz - 1.5);
  new PointLight({ x: tx, y: 3.0, z: tz, r: 1.0, g: 0.7, b: 0.3, intensity: 1.5, range: 12 });

  let bx = 8, bz = -5;
  addBlockHex(player, bx, 0, bz, 6, 0.15, 5, "#4A4540");
  addBlockHex(player, bx, 0.15, bz - 2.3, 6, 3.0, 0.4, "#7A6B55");
  addBlockHex(player, bx - 2.8, 0.15, bz, 0.4, 3.0, 5, "#7A6B55");
  addBlockHex(player, bx + 2.8, 0.15, bz, 0.4, 3.0, 5, "#7A6B55");
  addBlockHex(player, bx, 3.15, bz, 6.5, 0.2, 5.5, "#5A3A20");
  addBlockHex(player, bx + 0.5, 0.15, bz - 0.5, 0.6, 0.6, 0.4, "#3A3A3E", 0, { roughness: 0.3, metallic: 0.9 });
  addBlockHex(player, bx + 0.5, 0.75, bz - 0.5, 0.8, 0.15, 0.3, "#3A3A3E", 0, { roughness: 0.3, metallic: 0.9 });
  addBlockHex(player, bx - 1, 0.15, bz - 1, 1.5, 0.6, 1.5, "#2A2A2A");
  addDecoHex(bx - 1, 0.75, bz - 1, 1.2, 0.1, 1.2, "#FF4400", { emissive: [1.0, 0.3, 0.0], emissiveStrength: 5.0 });
  emitters.forgeFire = createFireEmitter(bx - 1, 0.9, bz - 1);
  emitters.forgeEmbers = createEmberEmitter(bx - 1, 1.5, bz - 1);
  new PointLight({ x: bx - 1, y: 1.5, z: bz - 1, r: 1.0, g: 0.4, b: 0.05, intensity: 2.0, range: 10 });
  addBlockHex(player, bx - 2, 0.15, bz + 1.5, 0.15, 1.5, 0.8, "#5B3A1E");

  for (let i = 0; i < 4; i++) {
    let mx = -2 + i * 3.5, mz = 5;
    addBlockHex(player, mx - 0.9, 0, mz - 0.6, 0.12, 2.2, 0.12, "#5B3A1E");
    addBlockHex(player, mx + 0.9, 0, mz - 0.6, 0.12, 2.2, 0.12, "#5B3A1E");
    addBlockHex(player, mx - 0.9, 0, mz + 0.6, 0.12, 2.2, 0.12, "#5B3A1E");
    addBlockHex(player, mx + 0.9, 0, mz + 0.6, 0.12, 2.2, 0.12, "#5B3A1E");
    let canopyColors = ["#AA3333", "#33AA55", "#3355AA", "#AA8833"];
    addBlockHex(player, mx, 2.2, mz, 2.2, 0.08, 1.6, canopyColors[i]);
    addBlockHex(player, mx, 0, mz, 1.8, 0.85, 1.2, "#6B5A3E");
    let wareColors = ["#CC4444", "#44CC44", "#4444CC", "#CCCC44"];
    for (let w = 0; w < 3; w++) {
      addDecoHex(mx - 0.5 + w * 0.5, 0.85, mz, 0.3, 0.2, 0.3, wareColors[(i + w) % 4]);
    }
  }

  let mtx = -5, mtz = -18;
  addBlockHex(player, mtx, 0, mtz, 4, 0.3, 4, "#4A4A5A");
  addBlockHex(player, mtx, 0.3, mtz, 3, 8, 3, "#5A5A6A");
  addDecoHex(mtx + 1.55, 4, mtz, 0.1, 0.8, 0.4, "#6688FF", { emissive: [0.3, 0.5, 1.0], emissiveStrength: 3.0 });
  addDecoHex(mtx - 1.55, 6, mtz, 0.1, 0.8, 0.4, "#6688FF", { emissive: [0.3, 0.5, 1.0], emissiveStrength: 3.0 });
  addDecoHex(mtx, 5, mtz + 1.55, 0.4, 0.8, 0.1, "#6688FF", { emissive: [0.3, 0.5, 1.0], emissiveStrength: 3.0 });
  addBlockHex(player, mtx, 8.3, mtz, 3.6, 0.3, 3.6, "#5A5A6A");
  addBlockHex(player, mtx - 1.3, 8.6, mtz, 0.4, 0.6, 0.4, "#5A5A6A");
  addBlockHex(player, mtx + 1.3, 8.6, mtz, 0.4, 0.6, 0.4, "#5A5A6A");
  addBlockHex(player, mtx, 8.6, mtz - 1.3, 0.4, 0.6, 0.4, "#5A5A6A");
  addBlockHex(player, mtx, 8.6, mtz + 1.3, 0.4, 0.6, 0.4, "#5A5A6A");
  emitters.mystic = createMysticEmitter(mtx, 9.2, mtz);
  new PointLight({ x: mtx, y: 9.5, z: mtz, r: 0.3, g: 0.5, b: 1.0, intensity: 2.5, range: 20 });

  addDecoration(15, -0.3, 3, 2.5, 0.4, 30, 0.12, 0.18, 0.25, { roughness: 0.1, metallic: 0.2 });
  addBlockHex(player, 15, 0, 3, 4, 0.4, 3, "#6B6560");
  addBlockHex(player, 13.5, 0.4, 1.8, 0.3, 0.6, 0.3, "#6B6560");
  addBlockHex(player, 16.5, 0.4, 1.8, 0.3, 0.6, 0.3, "#6B6560");
  addBlockHex(player, 13.5, 0.4, 4.2, 0.3, 0.6, 0.3, "#6B6560");
  addBlockHex(player, 16.5, 0.4, 4.2, 0.3, 0.6, 0.3, "#6B6560");
  emitters.streamMist = createWaterfallMist(15, 0.1, 3);

  let gx = 20, gz = -15;
  addBlockHex(player, gx, 0, gz, 10, 0.08, 8, "#2A2A22");
  for (let f = -4.5; f <= 4.5; f += 1.0) {
    addDecoHex(gx + f, 0.08, gz - 3.8, 0.08, 0.8, 0.08, "#3A3530");
    addDecoHex(gx + f, 0.08, gz + 3.8, 0.08, 0.8, 0.08, "#3A3530");
  }
  for (let f = -3.5; f <= 3.5; f += 1.0) {
    addDecoHex(gx - 4.8, 0.08, gz + f, 0.08, 0.8, 0.08, "#3A3530");
    addDecoHex(gx + 4.8, 0.08, gz + f, 0.08, 0.8, 0.08, "#3A3530");
  }
  let headstones = [
    [gx - 2.5, gz - 1.5], [gx - 0.5, gz - 2], [gx + 1.5, gz - 1],
    [gx - 1.5, gz + 1], [gx + 0.5, gz + 1.5], [gx + 3, gz + 0.5],
    [gx + 2.5, gz - 2], [gx - 3, gz + 0],
  ];
  for (let i = 0; i < headstones.length; i++) {
    let hx = headstones[i][0], hz = headstones[i][1];
    let ht = 0.5 + Math.random() * 0.5;
    addDecoHex(hx, 0.08, hz, 0.5, ht, 0.12, "#5A5A5A", { roughness: 0.95 });
  }
  emitters.graveyardDust = createDustEmitter(gx, 0.5, gz);

  let cfx = 5, cfz = 12;
  addBlockHex(player, cfx, 0, cfz, 1.6, 0.3, 1.6, "#4A4540");
  addDecoration(cfx, 0.3, cfz, 1.0, 0.15, 1.0, 0.15, 0.08, 0.05);
  addBlockHex(player, cfx - 2, 0, cfz, 1.5, 0.35, 0.35, "#5B3A1E");
  addBlockHex(player, cfx + 2, 0, cfz + 0.5, 1.5, 0.35, 0.35, "#5B3A1E");
  addBlockHex(player, cfx, 0, cfz - 2, 0.35, 0.35, 1.5, "#5B3A1E");
  emitters.campfire = createFireEmitter(cfx, 0.45, cfz);
  emitters.campEmbers = createEmberEmitter(cfx, 1.0, cfz);
  new PointLight({ x: cfx, y: 1.5, z: cfz, r: 1.0, g: 0.6, b: 0.2, intensity: 2.0, range: 15 });

  let treePositions = [
    [-18, 6], [-14, 12], [-22, -2], [12, 15], [18, 10],
    [-25, -10], [25, 8], [-10, 18], [8, -18], [-20, 15],
    [28, -5], [-28, 8], [22, 18], [-15, -25], [30, 15],
  ];
  for (let i = 0; i < treePositions.length; i++) {
    let treex = treePositions[i][0], treez = treePositions[i][1];
    let trunkH = 2.5 + Math.random() * 2;
    let leafSize = 1.8 + Math.random() * 1.5;
    addBlockHex(player, treex, 0, treez, 0.4, trunkH, 0.4, "#5B3A1E");
    let leafGreen = 0.25 + Math.random() * 0.2;
    addDecoration(treex, trunkH, treez, leafSize, leafSize * 0.6, leafSize, 0.15, leafGreen, 0.1);
    addDecoration(treex, trunkH + leafSize * 0.4, treez, leafSize * 0.7, leafSize * 0.5, leafSize * 0.7, 0.12, leafGreen + 0.05, 0.08);
  }

  let ax = -25, az = -18;
  addBlockHex(player, ax - 2, 0, az, 1.2, 4, 1.2, "#6A6A6A");
  addBlockHex(player, ax + 2, 0, az, 1.2, 4, 1.2, "#6A6A6A");
  addBlockHex(player, ax, 3.5, az, 5.5, 0.8, 1.2, "#6A6A6A", 3.5);
  addDecoHex(ax + 3, 0, az + 1, 0.8, 0.5, 0.6, "#5A5A5A");
  addDecoHex(ax - 1, 0, az + 1.5, 0.6, 0.3, 0.5, "#5A5A5A");
  emitters.archMystic = createMysticEmitter(ax, 2.0, az);
  new PointLight({ x: ax, y: 2.5, z: az, r: 0.4, g: 0.3, b: 1.0, intensity: 1.5, range: 8 });

  let dx = 30, dz = 0;
  addDecoration(dx + 5, -0.2, dz, 15, 0.3, 8, 0.1, 0.2, 0.35, { roughness: 0.05, metallic: 0.3 });
  addBlockHex(player, dx, 0, dz, 8, 0.2, 2.5, "#6B4A2E");
  addBlockHex(player, dx - 3, -0.5, dz - 1, 0.3, 0.8, 0.3, "#5B3A1E");
  addBlockHex(player, dx - 3, -0.5, dz + 1, 0.3, 0.8, 0.3, "#5B3A1E");
  addBlockHex(player, dx + 3, -0.5, dz - 1, 0.3, 0.8, 0.3, "#5B3A1E");
  addBlockHex(player, dx + 3, -0.5, dz + 1, 0.3, 0.8, 0.3, "#5B3A1E");
  addBlockHex(player, dx + 2, 0.2, dz + 0.5, 0.6, 0.8, 0.6, "#6B4A2E");
  addBlockHex(player, dx + 2.8, 0.2, dz - 0.5, 0.5, 0.7, 0.5, "#5B3A1E");
  emitters.dockMist = createWaterfallMist(dx + 5, 0.1, dz);

  let wtx = 6, wtz = -10;
  addBlockHex(player, wtx, 0, wtz, 2, 6, 2, "#6B5A40");
  addBlockHex(player, wtx, 6, wtz, 2.8, 0.2, 2.8, "#7B6A50");
  addBlockHex(player, wtx - 1.2, 6.2, wtz, 0.1, 0.8, 2.8, "#5B3A1E");
  addBlockHex(player, wtx + 1.2, 6.2, wtz, 0.1, 0.8, 2.8, "#5B3A1E");
  addBlockHex(player, wtx, 6.2, wtz - 1.2, 2.8, 0.8, 0.1, "#5B3A1E");
  addBlockHex(player, wtx, 6.2, wtz + 1.2, 2.8, 0.8, 0.1, "#5B3A1E");
  for (let s = 0; s < 12; s++) {
    addBlockHex(player, wtx + 1.5, s * 0.5, wtz - 0.8 + s * 0.15, 0.8, 0.5, 0.5, "#5B4A30");
  }
  emitters.watchFire = createFireEmitter(wtx, 7.2, wtz);
  new PointLight({ x: wtx, y: 7.5, z: wtz, r: 1.0, g: 0.7, b: 0.3, intensity: 2.0, range: 18 });

  emitters.ambientDust1 = createDustEmitter(0, 2, 0);
  emitters.ambientDust2 = createDustEmitter(-15, 3, 10);
  emitters.ambientDust3 = createDustEmitter(15, 2, -10);

  let pathPoints = [
    [3, 0], [5, -1], [7, -3], [9, -5], [11, -7],
    [-3, -1], [-5, -2], [-7, -4], [-9, -6], [-11, -8],
    [2, 3], [3, 6], [4, 9], [5, 12],
  ];
  for (let i = 0; i < pathPoints.length; i++) {
    let px = pathPoints[i][0], pz = pathPoints[i][1];
    let sw = 0.8 + Math.random() * 0.6;
    let sd = 0.8 + Math.random() * 0.6;
    addDecoration(px, 0.05, pz, sw, 0.06, sd, 0.4, 0.38, 0.35, { roughness: 0.95 });
  }

  Configuration.setAmbientColor(0.12, 0.1, 0.14);
}

// Game State

const SW = 1920;
const SH = 1080;

let playerHealth = 100;
let playerMaxHealth = 100;
let playerStamina = 100;
let playerMaxStamina = 100;
let staminaDrainRate = 25;
let staminaRegenRate = 15;
let staminaRegenDelay = 1.5;
let staminaRegenTimer = 0;
let staminaExhausted = false;

let fallDamageThreshold = 4.0;
let fallDamageMultiplier = 8.0;
let damageFlashTimer = 0;

const LOCATIONS = [
  { name: "Tavern",          x: -8,  z: -4,  radius: 6 },
  { name: "Blacksmith",      x: 8,   z: -5,  radius: 5 },
  { name: "Market Square",   x: 3,   z: 5,   radius: 8 },
  { name: "Mage Tower",      x: -5,  z: -18, radius: 5 },
  { name: "Town Square",     x: 0,   z: 0,   radius: 8 },
  { name: "Graveyard",       x: 20,  z: -15, radius: 7 },
  { name: "Campfire",        x: 5,   z: 12,  radius: 4 },
  { name: "Watchtower",      x: 6,   z: -10, radius: 4 },
  { name: "Ancient Archway", x: -25, z: -18, radius: 5 },
  { name: "Docks",           x: 30,  z: 0,   radius: 7 },
  { name: "Bridge",          x: 15,  z: 3,   radius: 4 },
];

let currentLocation = "";
let lastLocation = "";
let locationShowTimer = 0;
let locationFade = 0;

let frames = 0;
let fpsTimer = 0;
let fps = 0;
let gameTime = 0;

// Game Logic

function detectLocation(px, pz) {
  for (let i = 0; i < LOCATIONS.length; i++) {
    let loc = LOCATIONS[i];
    let dx = px - loc.x, dz = pz - loc.z;
    if (dx * dx + dz * dz < loc.radius * loc.radius) return loc.name;
  }
  return "Wilderness";
}

function updateStamina(dt, player) {
  let isSprinting = player.sprinting && player._groundSpeed > 0.5;

  if (isSprinting && !staminaExhausted) {
    playerStamina = Math.max(0, playerStamina - staminaDrainRate * dt);
    staminaRegenTimer = staminaRegenDelay;
    if (playerStamina <= 0) {
      staminaExhausted = true;
      player.sprintBlocked = true;
    }
  } else {
    if (staminaRegenTimer > 0) {
      staminaRegenTimer -= dt;
    } else {
      playerStamina = Math.min(playerMaxStamina, playerStamina + staminaRegenRate * dt);
    }
    if (staminaExhausted && playerStamina >= playerMaxStamina * 0.3) {
      staminaExhausted = false;
      player.sprintBlocked = false;
    }
  }
}

function updateFallDamage(player) {
  if (player.justLanded && player.landFallHeight > fallDamageThreshold) {
    let damage = (player.landFallHeight - fallDamageThreshold) * fallDamageMultiplier;
    playerHealth = Math.max(0, playerHealth - damage);
    damageFlashTimer = 0.35;
  }
}

// HUD Drawing

function drawBar(x, y, w, h, value, maxValue, r, g, b) {
  let pct = Math.max(0, Math.min(1, value / maxValue));
  GUI.rect(x, y, w, h, 0.05, 0.04, 0.03, 0.55);
  if (pct > 0) GUI.rect(x + 1, y + 1, (w - 2) * pct, h - 2, r, g, b, 0.85);
  GUI.rect(x, y, w, 1, 0.55, 0.45, 0.3, 0.35);
  GUI.rect(x, y + h - 1, w, 1, 0.55, 0.45, 0.3, 0.35);
  GUI.rect(x, y, 1, h, 0.55, 0.45, 0.3, 0.35);
  GUI.rect(x + w - 1, y, 1, h, 0.55, 0.45, 0.3, 0.35);
}

function drawCrosshair() {
  let cx = SW / 2;
  let cy = SH / 2;
  GUI.rect(cx - 1, cy - 1, 3, 3, 1, 1, 1, 0.55);
  let len = 12, gap = 5, t = 1.5;
  GUI.rect(cx - gap - len, cy - t / 2, len, t, 1, 1, 1, 0.3);
  GUI.rect(cx + gap, cy - t / 2, len, t, 1, 1, 1, 0.3);
  GUI.rect(cx - t / 2, cy - gap - len, t, len, 1, 1, 1, 0.3);
  GUI.rect(cx - t / 2, cy + gap, t, len, 1, 1, 1, 0.3);
}

function drawCompass(yaw) {
  let cx = SW / 2;
  let y = 20;
  let halfW = 180;

  GUI.rect(cx - halfW - 2, y - 2, halfW * 2 + 4, 28, 0, 0, 0, 0.35);
  GUI.rect(cx - 1, y - 5, 2, 5, 1.0, 0.85, 0.5, 0.85);

  let bearing = (-(yaw + Math.PI / 2)) * 180 / Math.PI;
  bearing = ((bearing % 360) + 360) % 360;

  for (let a = 0; a < 360; a += 5) {
    let diff = ((a - bearing + 540) % 360) - 180;
    let screenX = cx + (diff / 90) * halfW;
    if (screenX < cx - halfW || screenX > cx + halfW) continue;

    if (a % 90 === 0) {
      let labels = { 0: "N", 90: "E", 180: "S", 270: "W" };
      let isN = a === 0;
      GUI.text(labels[a], screenX - (isN ? 4 : 4), y + 2, 1.8, isN ? 1.0 : 0.85, isN ? 0.35 : 0.8, isN ? 0.3 : 0.7, 0.9);
    } else if (a % 45 === 0) {
      let labels = { 45: "NE", 135: "SE", 225: "SW", 315: "NW" };
      GUI.text(labels[a], screenX - 7, y + 4, 1.2, 0.55, 0.5, 0.45, 0.55);
    } else if (a % 15 === 0) {
      GUI.rect(screenX, y + 16, 1, 6, 0.45, 0.4, 0.3, 0.3);
    }
  }
}

function drawPlayerBars() {
  let barW = 240;
  let barH = 12;
  let x = 30;
  let baseY = SH - 70;

  let hpPct = playerHealth / playerMaxHealth;
  drawBar(x, baseY, barW, barH, playerHealth, playerMaxHealth,
    hpPct > 0.25 ? 0.7 : 0.9, hpPct > 0.25 ? 0.15 : 0.08, 0.12);
  GUI.text("HP", x, baseY - 18, 1.5, 0.85, 0.35, 0.3, 0.7);
  GUI.text(Math.ceil(playerHealth).toString(), x + barW + 8, baseY - 1, 1.4, 0.85, 0.35, 0.3, 0.55);

  if (hpPct <= 0.25 && hpPct > 0) {
    let pulse = 0.5 + Math.sin(gameTime * 4) * 0.2;
    GUI.rect(x + 1, baseY + 1, (barW - 2) * hpPct, barH - 2, 0.9, 0.1, 0.08, pulse);
  }

  let spY = baseY + barH + 8;
  drawBar(x, spY, barW, barH, playerStamina, playerMaxStamina,
    staminaExhausted ? 0.45 : 0.2, staminaExhausted ? 0.3 : 0.6, staminaExhausted ? 0.15 : 0.22);
  GUI.text("SP", x, spY - 18, 1.5, 0.35, 0.8, 0.45, 0.7);
  GUI.text(Math.ceil(playerStamina).toString(), x + barW + 8, spY - 1, 1.4, 0.35, 0.8, 0.45, 0.55);

  if (staminaExhausted) {
    let blink = 0.5 + Math.sin(gameTime * 6) * 0.35;
    GUI.text("EXHAUSTED", x + 60, spY + barH + 6, 1.3, 0.9, 0.5, 0.15, blink);
  }
}

function drawLocationName(dt) {
  if (currentLocation !== lastLocation) {
    lastLocation = currentLocation;
    locationShowTimer = 3.5;
    locationFade = 1.0;
  }
  if (locationShowTimer > 0) {
    locationShowTimer -= dt;
    if (locationShowTimer < 0.6) locationFade = Math.max(0, locationShowTimer / 0.6);
    // Try different character widths — adjust this number until centered
    let charW = 20;
    let tw = currentLocation.length * charW;
    GUI.text(currentLocation, (SW - tw) / 2, 62, 2.8, 0.95, 0.85, 0.6, locationFade * 0.85);
  }
}

function drawStatusIndicator(player) {
  let status = player.getStatus();
  if (status === "sprinting") {
    GUI.text("SPRINT", SW / 2 - 30, SH - 100, 1.5, 1.0, 0.85, 0.35, 0.6);
  } else if (status === "crouching") {
    GUI.text("CROUCH", SW / 2 - 32, SH - 100, 1.5, 0.5, 0.8, 1.0, 0.6);
  }
}

function drawDamageFlash(dt) {
  if (damageFlashTimer > 0) {
    damageFlashTimer -= dt;
    let a = (damageFlashTimer / 0.35) * 0.35;
    let t = 6;
    GUI.rect(0, 0, SW, t, 0.8, 0.08, 0.05, a);
    GUI.rect(0, SH - t, SW, t, 0.8, 0.08, 0.05, a);
    GUI.rect(0, 0, t, SH, 0.8, 0.08, 0.05, a);
    GUI.rect(SW - t, 0, t, SH, 0.8, 0.08, 0.05, a);
  }
}

function drawCoords(player) {
  let pos = player.getPosition();
  GUI.text(Math.floor(pos.x) + ", " + Math.floor(pos.z), SW - 100, SH - 28, 1.3, 0.55, 0.5, 0.4, 0.4);
}

function drawFPS() {
  GUI.text(fps.toString(), SW - 50, 16, 1.6, 0.65, 0.65, 0.65, 0.4);
}

function drawHUD(player, dt) {
  let pos = player.getPosition();
  currentLocation = detectLocation(pos.x, pos.z);

  updateStamina(dt, player);
  updateFallDamage(player);

  drawCrosshair();
  drawCompass(player.yaw);
  drawPlayerBars();
  drawLocationName(dt);
  drawStatusIndicator(player);
  drawDamageFlash(dt);
  drawCoords(player);
  drawFPS();
}

// Pause Menu

function drawPauseMenu() {
  GUI.rect(0, 0, SW, SH, 0, 0, 0, 0.65);
  GUI.text("PAUSED", SW / 2 - 62, SH / 2 - 100, 4.5, 0.95, 0.85, 0.6, 1.0);
  GUI.rect(SW / 2 - 100, SH / 2 - 48, 200, 1, 0.65, 0.55, 0.35, 0.3);

  let sy = SH / 2 - 15;
  let lh = 32;
  let keys = ["W A S D", "SHIFT", "CTRL / C", "SPACE", "ESC"];
  let acts = ["Move", "Sprint", "Crouch", "Jump", "Resume"];
  for (let i = 0; i < keys.length; i++) {
    GUI.text(keys[i], SW / 2 - 90, sy + i * lh, 1.7, 0.95, 0.85, 0.6, 0.8);
    GUI.text(acts[i], SW / 2 + 30, sy + i * lh, 1.7, 0.6, 0.55, 0.45, 0.6);
  }
  GUI.text("Press ESC to resume", SW / 2 - 78, sy + keys.length * lh + 20, 1.4, 0.4, 0.38, 0.33, 0.45);
}

// Main

let player;
let menuOpen = false;

export function onStart() {
  try {
    player = new FirstPersonController({
      x: 0, z: 8, eyeHeight: 1.7, yaw: -Math.PI / 2,
      moveSpeed: 5.0, sprintMultiplier: 1.8,
      acceleration: 40.0, airFriction: 2.0, airControl: 0.3,
      jumpForce: 7.0, gravity: -20.0,
      fov: 70, sprintFov: 82,
      playerHeight: 1.7,
      bounds: { minX: -98, maxX: 98, minZ: -98, maxZ: 98 },
    });

    buildScene(player);

    Configuration.setShadowResolution(4096);
    Configuration.setSkyboxTopColor(0.08, 0.12, 0.28);
    Configuration.setSkyboxBottomColor(0.95, 0.55, 0.25);

    // try {
    //   Pipeline.removeStage("chromatic_aberration");
    //   Pipeline.removeStage("color_grading");
    //   Pipeline.removeStage("vignette");
    // } catch (e) {
    //   Debug.log("Pipeline cleanup: " + e.message);
    // }

    Window.fullscreen();
    Input.lockCursor();
  } catch (e) {
    Debug.log("Error in onStart, " + e + ", " + e.stack);
  }
}

export function onUpdate(dt) {
  if (!player) return;

  if (Input.keyPressed("Escape")) {
    menuOpen = !menuOpen;
    if (menuOpen) Input.unlockCursor();
    else Input.lockCursor();
  }

  if (menuOpen) {
    drawPauseMenu();
    return;
  }

  player.update(dt);
  gameTime += dt;
  drawHUD(player, dt);

  frames++;
  fpsTimer += dt;
  if (fpsTimer >= 1.0) {
    fps = frames;
    frames = 0;
    fpsTimer -= 1.0;
  }
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