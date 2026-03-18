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

  // Grass patches (subtle color variation)
  for (let i = 0; i < 20; i++) {
    let gx = (Math.random() - 0.5) * 80;
    let gz = (Math.random() - 0.5) * 80;
    let gs = 2 + Math.random() * 5;
    let gd = 2 + Math.random() * 5;
    let green = 0.25 + Math.random() * 0.15;
    addDecoration(gx, 0.05, gz, gs, 0.02, gd, 0.2, green, 0.12, { roughness: 1.0 });
  }

  // Cobblestone plaza
  addBlockHex(player, 0, 0, 0, 14, 0.12, 14, "#5C5549");

  // Central well
  addBlockHex(player, 0, 0.12, 0, 2.4, 0.8, 2.4, "#6B6560", 0, { roughness: 0.9 });
  // Well water (dark reflective surface)
  addDecoration(0, 0.85, 0, 1.8, 0.05, 1.8, 0.1, 0.15, 0.25, { roughness: 0.1, metallic: 0.3 });
  // Well posts
  addBlockHex(player, -0.9, 0.92, -0.9, 0.15, 1.8, 0.15, "#5B3A1E");
  addBlockHex(player, 0.9, 0.92, -0.9, 0.15, 1.8, 0.15, "#5B3A1E");
  addBlockHex(player, 0, 2.72, -0.9, 2.2, 0.15, 0.15, "#5B3A1E");
  // Well roof
  addBlockHex(player, 0, 2.87, -0.9, 2.6, 0.08, 1.2, "#8B4513");

  let tx = -8, tz = -4;
  // Foundation
  addBlockHex(player, tx, 0, tz, 8, 0.2, 6, "#4A4540");
  // Walls
  addBlockHex(player, tx, 0.2, tz - 2.8, 8, 3.5, 0.4, "#8B7355");
  addBlockHex(player, tx, 0.2, tz + 2.8, 8, 3.5, 0.4, "#8B7355");
  addBlockHex(player, tx - 3.8, 0.2, tz, 0.4, 3.5, 6, "#8B7355");
  addBlockHex(player, tx + 3.8, 0.2, tz, 0.4, 3.5, 6, "#8B7355");
  // Door frame opening
  addBlockHex(player, tx + 3.8, 2.5, tz, 0.5, 1.2, 1.5, "#8B7355", 2.5);
  // Roof
  addBlockHex(player, tx, 3.7, tz, 9, 0.2, 7, "#6B3320");
  addBlockHex(player, tx, 3.9, tz, 7, 0.15, 5, "#6B3320");
  // Chimney
  addBlockHex(player, tx - 2.5, 3.9, tz - 1.5, 1.0, 2.0, 1.0, "#5A5550");
  // Tavern sign (glowing)
  addDecoHex(tx + 4.2, 2.8, tz, 0.1, 0.6, 1.2, "#C8A850", {
    emissive: [0.8, 0.6, 0.1], emissiveStrength: 2.0
  });
  // Interior - tables
  addBlockHex(player, tx - 1, 0.2, tz - 0.5, 1.2, 0.7, 0.8, "#5B3A1E");
  addBlockHex(player, tx + 1.5, 0.2, tz + 0.5, 1.0, 0.7, 1.0, "#5B3A1E");
  // Interior - bar counter
  addBlockHex(player, tx - 2.5, 0.2, tz, 1.0, 1.0, 4.0, "#4A2A0E");
  // Tavern fire
  emitters.tavernFire = createFireEmitter(tx - 2.5, 4.2, tz - 1.5);
  emitters.tavernEmbers = createEmberEmitter(tx - 2.5, 4.8, tz - 1.5);

  // Tavern warm light
  new PointLight({ x: tx, y: 3.0, z: tz, r: 1.0, g: 0.7, b: 0.3, intensity: 1.5, range: 12 });

  let bx = 8, bz = -5;
  // Forge building
  addBlockHex(player, bx, 0, bz, 6, 0.15, 5, "#4A4540");
  addBlockHex(player, bx, 0.15, bz - 2.3, 6, 3.0, 0.4, "#7A6B55");
  addBlockHex(player, bx - 2.8, 0.15, bz, 0.4, 3.0, 5, "#7A6B55");
  addBlockHex(player, bx + 2.8, 0.15, bz, 0.4, 3.0, 5, "#7A6B55");
  // Open front
  addBlockHex(player, bx, 3.15, bz, 6.5, 0.2, 5.5, "#5A3A20");
  // Anvil
  addBlockHex(player, bx + 0.5, 0.15, bz - 0.5, 0.6, 0.6, 0.4, "#3A3A3E", 0, { roughness: 0.3, metallic: 0.9 });
  addBlockHex(player, bx + 0.5, 0.75, bz - 0.5, 0.8, 0.15, 0.3, "#3A3A3E", 0, { roughness: 0.3, metallic: 0.9 });
  // Forge pit
  addBlockHex(player, bx - 1, 0.15, bz - 1, 1.5, 0.6, 1.5, "#2A2A2A");
  addDecoHex(bx - 1, 0.75, bz - 1, 1.2, 0.1, 1.2, "#FF4400", {
    emissive: [1.0, 0.3, 0.0], emissiveStrength: 5.0
  });
  // Forge fire particles
  emitters.forgeFire = createFireEmitter(bx - 1, 0.9, bz - 1);
  emitters.forgeEmbers = createEmberEmitter(bx - 1, 1.5, bz - 1);
  // Forge light
  new PointLight({ x: bx - 1, y: 1.5, z: bz - 1, r: 1.0, g: 0.4, b: 0.05, intensity: 2.0, range: 10 });

  // Weapon rack
  addBlockHex(player, bx - 2, 0.15, bz + 1.5, 0.15, 1.5, 0.8, "#5B3A1E");

  for (let i = 0; i < 4; i++) {
    let mx = -2 + i * 3.5, mz = 5;
    // Posts
    addBlockHex(player, mx - 0.9, 0, mz - 0.6, 0.12, 2.2, 0.12, "#5B3A1E");
    addBlockHex(player, mx + 0.9, 0, mz - 0.6, 0.12, 2.2, 0.12, "#5B3A1E");
    addBlockHex(player, mx - 0.9, 0, mz + 0.6, 0.12, 2.2, 0.12, "#5B3A1E");
    addBlockHex(player, mx + 0.9, 0, mz + 0.6, 0.12, 2.2, 0.12, "#5B3A1E");
    // Canopy
    let canopyColors = ["#AA3333", "#33AA55", "#3355AA", "#AA8833"];
    addBlockHex(player, mx, 2.2, mz, 2.2, 0.08, 1.6, canopyColors[i]);
    // Counter
    addBlockHex(player, mx, 0, mz, 1.8, 0.85, 1.2, "#6B5A3E");
    // Wares (small colorful blocks)
    let wareColors = ["#CC4444", "#44CC44", "#4444CC", "#CCCC44"];
    for (let w = 0; w < 3; w++) {
      addDecoHex(mx - 0.5 + w * 0.5, 0.85, mz, 0.3, 0.2, 0.3, wareColors[(i + w) % 4]);
    }
  }

  let mtx = -5, mtz = -18;

  // Base
  addBlockHex(player, mtx, 0, mtz, 4, 0.3, 4, "#4A4A5A");

  // Tower body
  addBlockHex(player, mtx, 0.3, mtz, 3, 8, 3, "#5A5A6A");

  // Windows (emissive)
  addDecoHex(mtx + 1.55, 4, mtz, 0.1, 0.8, 0.4, "#6688FF", {
    emissive: [0.3, 0.5, 1.0], emissiveStrength: 3.0
  });

  addDecoHex(mtx - 1.55, 6, mtz, 0.1, 0.8, 0.4, "#6688FF", {
    emissive: [0.3, 0.5, 1.0], emissiveStrength: 3.0
  });

  addDecoHex(mtx, 5, mtz + 1.55, 0.4, 0.8, 0.1, "#6688FF", {
    emissive: [0.3, 0.5, 1.0], emissiveStrength: 3.0
  });

  // Tower top
  addBlockHex(player, mtx, 8.3, mtz, 3.6, 0.3, 3.6, "#5A5A6A");

  // Battlement
  addBlockHex(player, mtx - 1.3, 8.6, mtz, 0.4, 0.6, 0.4, "#5A5A6A");
  addBlockHex(player, mtx + 1.3, 8.6, mtz, 0.4, 0.6, 0.4, "#5A5A6A");
  addBlockHex(player, mtx, 8.6, mtz - 1.3, 0.4, 0.6, 0.4, "#5A5A6A");
  addBlockHex(player, mtx, 8.6, mtz + 1.3, 0.4, 0.6, 0.4, "#5A5A6A");

  // Mystic particles at top
  emitters.mystic = createMysticEmitter(mtx, 9.2, mtz);

  // Tower light
  new PointLight({ x: mtx, y: 9.5, z: mtz, r: 0.3, g: 0.5, b: 1.0, intensity: 2.5, range: 20 });

  // Stream bed (dark)
  addDecoration(15, -0.3, 3, 2.5, 0.4, 30, 0.12, 0.18, 0.25, { roughness: 0.1, metallic: 0.2 });

  // Bridge
  addBlockHex(player, 15, 0, 3, 4, 0.4, 3, "#6B6560");
  addBlockHex(player, 13.5, 0.4, 1.8, 0.3, 0.6, 0.3, "#6B6560");
  addBlockHex(player, 16.5, 0.4, 1.8, 0.3, 0.6, 0.3, "#6B6560");
  addBlockHex(player, 13.5, 0.4, 4.2, 0.3, 0.6, 0.3, "#6B6560");
  addBlockHex(player, 16.5, 0.4, 4.2, 0.3, 0.6, 0.3, "#6B6560");

  // Mist near stream
  emitters.streamMist = createWaterfallMist(15, 0.1, 3);

  let gx = 20, gz = -15;
  addBlockHex(player, gx, 0, gz, 10, 0.08, 8, "#2A2A22");

  // Fence
  for (let f = -4.5; f <= 4.5; f += 1.0) {
    addDecoHex(gx + f, 0.08, gz - 3.8, 0.08, 0.8, 0.08, "#3A3530");
    addDecoHex(gx + f, 0.08, gz + 3.8, 0.08, 0.8, 0.08, "#3A3530");
  }

  for (let f = -3.5; f <= 3.5; f += 1.0) {
    addDecoHex(gx - 4.8, 0.08, gz + f, 0.08, 0.8, 0.08, "#3A3530");
    addDecoHex(gx + 4.8, 0.08, gz + f, 0.08, 0.8, 0.08, "#3A3530");
  }

  // Headstones
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

  // Eerie dust
  emitters.graveyardDust = createDustEmitter(gx, 0.5, gz);

  let cfx = 5, cfz = 12;

  // Fire pit ring
  addBlockHex(player, cfx, 0, cfz, 1.6, 0.3, 1.6, "#4A4540");
  addDecoration(cfx, 0.3, cfz, 1.0, 0.15, 1.0, 0.15, 0.08, 0.05);

  // Logs around fire
  addBlockHex(player, cfx - 2, 0, cfz, 1.5, 0.35, 0.35, "#5B3A1E");
  addBlockHex(player, cfx + 2, 0, cfz + 0.5, 1.5, 0.35, 0.35, "#5B3A1E");
  addBlockHex(player, cfx, 0, cfz - 2, 0.35, 0.35, 1.5, "#5B3A1E");

  // Campfire
  emitters.campfire = createFireEmitter(cfx, 0.45, cfz);
  emitters.campEmbers = createEmberEmitter(cfx, 1.0, cfz);

  // Campfire light
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

    // Trunk
    addBlockHex(player, treex, 0, treez, 0.4, trunkH, 0.4, "#5B3A1E");

    // Canopy layers
    let leafGreen = 0.25 + Math.random() * 0.2;
    addDecoration(treex, trunkH, treez, leafSize, leafSize * 0.6, leafSize, 0.15, leafGreen, 0.1);
    addDecoration(treex, trunkH + leafSize * 0.4, treez, leafSize * 0.7, leafSize * 0.5, leafSize * 0.7, 0.12, leafGreen + 0.05, 0.08);
  }

  let ax = -25, az = -18;
  addBlockHex(player, ax - 2, 0, az, 1.2, 4, 1.2, "#6A6A6A");
  addBlockHex(player, ax + 2, 0, az, 1.2, 4, 1.2, "#6A6A6A");
  addBlockHex(player, ax, 3.5, az, 5.5, 0.8, 1.2, "#6A6A6A", 3.5);

  // Broken pieces
  addDecoHex(ax + 3, 0, az + 1, 0.8, 0.5, 0.6, "#5A5A5A");
  addDecoHex(ax - 1, 0, az + 1.5, 0.6, 0.3, 0.5, "#5A5A5A");

  // Mystic glow in archway
  emitters.archMystic = createMysticEmitter(ax, 2.0, az);
  new PointLight({ x: ax, y: 2.5, z: az, r: 0.4, g: 0.3, b: 1.0, intensity: 1.5, range: 8 });

  let dx = 30, dz = 0;

  // Water area
  addDecoration(dx + 5, -0.2, dz, 15, 0.3, 8, 0.1, 0.2, 0.35, { roughness: 0.05, metallic: 0.3 });

  // Pier planks
  addBlockHex(player, dx, 0, dz, 8, 0.2, 2.5, "#6B4A2E");

  // Pier posts
  addBlockHex(player, dx - 3, -0.5, dz - 1, 0.3, 0.8, 0.3, "#5B3A1E");
  addBlockHex(player, dx - 3, -0.5, dz + 1, 0.3, 0.8, 0.3, "#5B3A1E");
  addBlockHex(player, dx + 3, -0.5, dz - 1, 0.3, 0.8, 0.3, "#5B3A1E");
  addBlockHex(player, dx + 3, -0.5, dz + 1, 0.3, 0.8, 0.3, "#5B3A1E");

  // Barrel on pier
  addBlockHex(player, dx + 2, 0.2, dz + 0.5, 0.6, 0.8, 0.6, "#6B4A2E");
  addBlockHex(player, dx + 2.8, 0.2, dz - 0.5, 0.5, 0.7, 0.5, "#5B3A1E");

  // Mist
  emitters.dockMist = createWaterfallMist(dx + 5, 0.1, dz);

  let wtx = 6, wtz = -10;
  addBlockHex(player, wtx, 0, wtz, 2, 6, 2, "#6B5A40");
  addBlockHex(player, wtx, 6, wtz, 2.8, 0.2, 2.8, "#7B6A50");

  // Railing
  addBlockHex(player, wtx - 1.2, 6.2, wtz, 0.1, 0.8, 2.8, "#5B3A1E");
  addBlockHex(player, wtx + 1.2, 6.2, wtz, 0.1, 0.8, 2.8, "#5B3A1E");
  addBlockHex(player, wtx, 6.2, wtz - 1.2, 2.8, 0.8, 0.1, "#5B3A1E");
  addBlockHex(player, wtx, 6.2, wtz + 1.2, 2.8, 0.8, 0.1, "#5B3A1E");

  // Stairs
  for (let s = 0; s < 12; s++) {
    addBlockHex(player, wtx + 1.5, s * 0.5, wtz - 0.8 + s * 0.15, 0.8, 0.5, 0.5, "#5B4A30");
  }

  // Torch at top
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

let animatedLights = [];
let gameTime = 0;

function updateAnimations(dt) {
  gameTime += dt;

  // Flicker campfire and forge lights by modulating particle rates
  // (Lights don't have setIntensity per-frame yet, but particles give the visual flicker)
}

let frames = 0;
let fpsTimer = 0;
let fps = 0;

function drawHUD(player) {
  let pos = player.getPosition();
  let status = player.getStatus();

  GUI.text(pos.x.toFixed(1) + ", " + pos.y.toFixed(1) + ", " + pos.z.toFixed(1), 10, 10, 2.0, 0.9, 0.9, 0.9, 0.7);
  GUI.text("FPS: " + fps, 10, 35, 2.5, 1, 1, 1, 0.9);

  // Crosshair
  GUI.rect(640 - 1, 360 - 8, 2, 16, 1, 1, 1, 0.5);
  GUI.rect(640 - 8, 360 - 1, 16, 2, 1, 1, 1, 0.5);

  // Status
  if (status === "sprinting") {
    GUI.text("SPRINTING", 10, 680, 1.5, 1.0, 0.8, 0.3, 0.8);
  } else if (status === "crouching") {
    GUI.text("CROUCHING", 10, 680, 1.5, 0.5, 0.8, 1.0, 0.8);
  }
}

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

    try {
      Pipeline.removeStage("chromatic_aberration");
      Pipeline.removeStage("color_grading");
      Pipeline.removeStage("vignette");
    } catch (e) {
      Debug.log("Pipeline cleanup: " + e.message);
    }

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
    if (menuOpen) {
      Input.unlockCursor();
    } else {
      Input.lockCursor();
    }
  }

  if (menuOpen) {
    GUI.rect(0, 0, 9999, 9999, 0, 0, 0, 0.6);
    GUI.text("PAUSED", 560, 300, 4.0, 1, 1, 1, 1);
    GUI.text("Press ESC to resume", 530, 360, 2.0, 0.7, 0.7, 0.7, 1);
    GUI.text("WASD - Move", 530, 420, 1.5, 0.6, 0.6, 0.6, 0.8);
    GUI.text("SHIFT - Sprint", 530, 445, 1.5, 0.6, 0.6, 0.6, 0.8);
    GUI.text("CTRL/C - Crouch", 530, 470, 1.5, 0.6, 0.6, 0.6, 0.8);
    GUI.text("SPACE - Jump", 530, 495, 1.5, 0.6, 0.6, 0.6, 0.8);
    return;
  }

  player.update(dt);
  updateAnimations(dt);
  drawHUD(player);

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