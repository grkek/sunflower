import { Canvas, Canvas3D } from "canvas";

// ═══════════════════════════════════════════════════════════════
//  KeyState — normalizes GTK key case mismatch
// ═══════════════════════════════════════════════════════════════
class KeyState {
  constructor(scene) {
    this.scene = scene;
    this.held = {};
    let self = this;
    scene.onKeyDown(function (keyName) {
      self.held[self._n(keyName)] = true;
    });
    scene.onKeyUp(function (keyName) {
      delete self.held[self._n(keyName)];
    });
  }
  _n(k) { return k.length === 1 ? k.toLowerCase() : k; }
  isDown(key) { return this.held[this._n(key)] === true; }
}

// ═══════════════════════════════════════════════════════════════
//  FirstPersonController
// ═══════════════════════════════════════════════════════════════
class FirstPersonController {
  constructor(scene, keys, opts) {
    this.scene = scene;
    this.keys = keys;
    this.x = opts.x || 0;
    this.z = opts.z || 0;
    this.eyeHeight = opts.eyeHeight || 1.7;
    this.y = this.eyeHeight;
    this.yaw = opts.yaw || 0;
    this.pitch = opts.pitch || 0;

    this.moveSpeed = opts.moveSpeed || 5.0;
    this.sprintMultiplier = opts.sprintMultiplier || 1.8;

    this.mouseSensitivity = opts.mouseSensitivity || 0.003;
    this.pitchLimit = opts.pitchLimit || 1.48;
    this.smoothLook = opts.smoothLook !== false;
    this.lookSmoothing = opts.lookSmoothing || 0.15;

    this.jumpForce = opts.jumpForce || 7.0;
    this.gravity = opts.gravity || -20.0;
    this.coyoteTime = opts.coyoteTime || 0.12;
    this.jumpBuffer = opts.jumpBuffer || 0.1;

    this.playerRadius = opts.playerRadius || 0.35;
    this.stepHeight = opts.stepHeight || 0.3;
    this.playerHeight = opts.playerHeight || 1.7;
    this.obstacles = [];
    this.bounds = opts.bounds || null;

    this.velX = 0; this.velZ = 0; this.velY = 0;
    this.onGround = false;
    this.groundTimer = 0;
    this.jumpBufferTimer = 0;
    this.sprinting = false;
    this.crouching = false;
    this.crouchHeight = 1.0;
    this.standHeight = this.eyeHeight;
    this.currentEyeHeight = this.eyeHeight;

    this.targetYaw = this.yaw;
    this.targetPitch = this.pitch;

    this.headBobPhase = 0;
    this.headBobAmount = 0;
    this.headBobX = 0;
    this.headBobY = 0;

    this.viewPunchPitch = 0;
    this.viewPunchYaw = 0;
    this.viewPunchDecay = 8.0;

    this.landingDip = 0;
    this.landingDipVel = 0;
    this.wasOnGround = true;
    this.fallStartY = this.y;

    this.lastMouseX = -1;
    this.lastMouseY = -1;
    this.mouseDeltaX = 0;
    this.mouseDeltaY = 0;

    this.baseFov = opts.fov || 70;
    this.sprintFov = opts.sprintFov || 80;
    this.currentFov = this.baseFov;

    this._eyeX = this.x;
    this._eyeY = this.y;
    this._eyeZ = this.z;
    this._finalYaw = this.yaw;
    this._finalPitch = this.pitch;
    this._dirX = 0; this._dirY = 0; this._dirZ = -1;
    this._groundSpeed = 0;
    this._moving = false;

    this._airFriction = opts.airFriction || 2.0;
    this._airControl = opts.airControl || 0.3;
    this._acceleration = opts.acceleration || 40.0;

    this._bindInput();
  }

  // minH = bottom of the obstacle (for elevated obstacles like arches/bridges)
  addObstacle(x, z, halfW, halfD, height, minH) {
    this.obstacles.push({
      x: x, z: z, halfW: halfW, halfD: halfD,
      height: height,
      minH: minH || 0,
    });
  }

  addViewPunch(p, y) { this.viewPunchPitch += p; this.viewPunchYaw += y; }

  _bindInput() {
    let self = this;
    this.scene.onMouseMove(function (mx, my) {
      if (self.lastMouseX < 0) { self.lastMouseX = mx; self.lastMouseY = my; return; }
      self.mouseDeltaX += (mx - self.lastMouseX);
      self.mouseDeltaY += (my - self.lastMouseY);
      self.lastMouseX = mx;
      self.lastMouseY = my;
    });
  }

  _collidesAt(nx, nz, feetY) {
    let r = this.playerRadius;
    let headY = feetY + this.playerHeight;
    for (let i = 0; i < this.obstacles.length; i++) {
      let ob = this.obstacles[i];
      // Vertical overlap check: player body [feetY..headY] vs obstacle [ob.minH..ob.height]
      // Player can step over if feetY is near the top (stepHeight)
      if (feetY >= ob.height - this.stepHeight) continue;
      // Player walks under if their head is below the obstacle bottom
      if (headY <= ob.minH) continue;
      // Player is fully below an elevated obstacle
      if (ob.minH > 0 && feetY < ob.minH && headY <= ob.minH) continue;

      let cx = Math.max(ob.x - ob.halfW, Math.min(nx, ob.x + ob.halfW));
      let cz = Math.max(ob.z - ob.halfD, Math.min(nz, ob.z + ob.halfD));
      let dx = nx - cx, dz = nz - cz;
      if (dx * dx + dz * dz < r * r) return true;
    }
    return false;
  }

  _getFloorAt(nx, nz) {
    let r = this.playerRadius;
    let feetY = this.y - this.currentEyeHeight;
    let floor = 0;
    for (let i = 0; i < this.obstacles.length; i++) {
      let ob = this.obstacles[i];
      let cx = Math.max(ob.x - ob.halfW, Math.min(nx, ob.x + ob.halfW));
      let cz = Math.max(ob.z - ob.halfD, Math.min(nz, ob.z + ob.halfD));
      let dx = nx - cx, dz = nz - cz;
      if (dx * dx + dz * dz < r * r) {
        if (ob.height > floor && feetY >= ob.height - this.stepHeight - 0.05) {
          floor = ob.height;
        }
      }
    }
    return floor;
  }

  _slideMove(nx, nz) {
    let fy = this.y - this.currentEyeHeight;
    if (!this._collidesAt(nx, nz, fy)) { this.x = nx; this.z = nz; return; }
    if (!this._collidesAt(nx, this.z, fy)) { this.x = nx; this.velZ *= 0.2; return; }
    if (!this._collidesAt(this.x, nz, fy)) { this.z = nz; this.velX *= 0.2; return; }
    this.velX *= 0.1; this.velZ *= 0.1;
  }

  update(dt) {
    if (dt <= 0 || dt > 0.1) dt = 0.016;
    let k = this.keys;

    // Mouse look
    this.targetYaw += this.mouseDeltaX * this.mouseSensitivity;
    this.targetPitch -= this.mouseDeltaY * this.mouseSensitivity;
    this.mouseDeltaX = 0; this.mouseDeltaY = 0;
    if (this.targetPitch > this.pitchLimit) this.targetPitch = this.pitchLimit;
    if (this.targetPitch < -this.pitchLimit) this.targetPitch = -this.pitchLimit;

    if (this.smoothLook) {
      let t = 1.0 - Math.pow(this.lookSmoothing, dt * 60);
      this.yaw += (this.targetYaw - this.yaw) * t;
      this.pitch += (this.targetPitch - this.pitch) * t;
    } else {
      this.yaw = this.targetYaw;
      this.pitch = this.targetPitch;
    }

    this.viewPunchPitch -= this.viewPunchPitch * this.viewPunchDecay * dt;
    this.viewPunchYaw -= this.viewPunchYaw * this.viewPunchDecay * dt;

    // Sprint / crouch
    this.sprinting = k.isDown("Shift_L") || k.isDown("Shift_R");
    this.crouching = k.isDown("Control_L") || k.isDown("Control_R") || k.isDown("c");
    let targetEye = this.crouching ? this.crouchHeight : this.standHeight;
    this.currentEyeHeight += (targetEye - this.currentEyeHeight) * Math.min(1, dt * 12);
    let maxSpeed = this.moveSpeed * (this.sprinting ? this.sprintMultiplier : 1.0);
    if (this.crouching) maxSpeed *= 0.5;

    // Movement input
    let fX = Math.cos(this.yaw), fZ = Math.sin(this.yaw);
    let rX = Math.cos(this.yaw + Math.PI / 2), rZ = Math.sin(this.yaw + Math.PI / 2);
    let wX = 0, wZ = 0;
    if (k.isDown("w")) { wX += fX; wZ += fZ; }
    if (k.isDown("s")) { wX -= fX; wZ -= fZ; }
    if (k.isDown("a")) { wX -= rX; wZ -= rZ; }
    if (k.isDown("d")) { wX += rX; wZ += rZ; }
    let wLen = Math.sqrt(wX * wX + wZ * wZ);
    if (wLen > 0.001) { wX /= wLen; wZ /= wLen; }

    let hasInput = wLen > 0.001;

    if (this.onGround) {
      if (hasInput) {
        let tVx = wX * maxSpeed;
        let tVz = wZ * maxSpeed;
        let blend = 1.0 - Math.pow(0.0001, dt);
        this.velX += (tVx - this.velX) * blend;
        this.velZ += (tVz - this.velZ) * blend;
      } else {
        let brake = 1.0 - Math.pow(0.00001, dt);
        this.velX *= (1.0 - brake);
        this.velZ *= (1.0 - brake);
        let spd = Math.sqrt(this.velX * this.velX + this.velZ * this.velZ);
        if (spd < 0.1) { this.velX = 0; this.velZ = 0; }
      }
    } else {
      let fric = this._airFriction;
      let accel = this._acceleration * this._airControl;
      let spd = Math.sqrt(this.velX * this.velX + this.velZ * this.velZ);
      if (spd > 0.01) {
        let drop = spd * fric * dt;
        let ns = Math.max(spd - drop, 0);
        this.velX *= ns / spd; this.velZ *= ns / spd;
      }
      if (hasInput) {
        let cs = this.velX * wX + this.velZ * wZ;
        let add = maxSpeed - cs;
        if (add > 0) {
          let as2 = accel * dt * maxSpeed;
          if (as2 > add) as2 = add;
          this.velX += wX * as2; this.velZ += wZ * as2;
        }
      }
    }

    this._slideMove(this.x + this.velX * dt, this.z + this.velZ * dt);

    if (this.bounds) {
      let b = this.bounds;
      if (this.x < b.minX) { this.x = b.minX; this.velX = 0; }
      if (this.x > b.maxX) { this.x = b.maxX; this.velX = 0; }
      if (this.z < b.minZ) { this.z = b.minZ; this.velZ = 0; }
      if (this.z > b.maxZ) { this.z = b.maxZ; this.velZ = 0; }
    }

    // Jump
    if (this.onGround) this.groundTimer = this.coyoteTime; else this.groundTimer -= dt;
    if (k.isDown("space")) this.jumpBufferTimer = this.jumpBuffer; else this.jumpBufferTimer -= dt;
    if (this.jumpBufferTimer > 0 && this.groundTimer > 0) {
      this.velY = this.jumpForce; this.onGround = false;
      this.groundTimer = 0; this.jumpBufferTimer = 0; this.fallStartY = this.y;
    }

    // Gravity
    if (!this.onGround) this.velY += this.gravity * dt;
    this.y += this.velY * dt;

    // Floor detection
    let floorHeight = this._getFloorAt(this.x, this.z);
    let feetTarget = floorHeight + this.currentEyeHeight;

    this.wasOnGround = this.onGround;
    if (this.y <= feetTarget) {
      if (!this.onGround && this.velY < -2) {
        this.landingDipVel = -Math.min((this.fallStartY - this.y) * 0.02, 0.4);
      }
      this.y = feetTarget; this.velY = 0; this.onGround = true;
    } else {
      this.onGround = false;
      if (this.wasOnGround && this.velY <= 0) this.fallStartY = this.y;
    }

    // Landing dip spring
    this.landingDip += this.landingDipVel;
    this.landingDipVel -= this.landingDip * 80 * dt;
    this.landingDipVel *= Math.pow(0.0001, dt);
    if (Math.abs(this.landingDip) < 0.001 && Math.abs(this.landingDipVel) < 0.001) {
      this.landingDip = 0; this.landingDipVel = 0;
    }

    // Head bob
    let gs = Math.sqrt(this.velX * this.velX + this.velZ * this.velZ);
    let moving = gs > 0.5 && this.onGround;
    if (moving) {
      let bf = this.sprinting ? 9.0 : 7.0;
      let sf = Math.min(gs / this.moveSpeed, 1.2);
      this.headBobPhase += dt * bf * sf;
      this.headBobY = Math.sin(this.headBobPhase) * (this.sprinting ? 0.025 : 0.018) * sf;
      this.headBobX = Math.cos(this.headBobPhase * 0.5) * (this.sprinting ? 0.015 : 0.01) * sf;
      this.headBobAmount = sf;
    } else {
      this.headBobPhase *= 0.9; this.headBobY *= 0.85; this.headBobX *= 0.85; this.headBobAmount *= 0.9;
    }

    // FOV
    let tf = this.sprinting && moving ? this.sprintFov : this.baseFov;
    this.currentFov += (tf - this.currentFov) * Math.min(1, dt * 8);

    // Camera
    let fp = this.pitch + this.viewPunchPitch;
    let fy2 = this.yaw + this.viewPunchYaw;
    let eyeY = this.y + this.headBobY + this.landingDip;
    let eyeX = this.x + this.headBobX * Math.cos(this.yaw + Math.PI / 2);
    let eyeZ = this.z + this.headBobX * Math.sin(this.yaw + Math.PI / 2);
    let dX = Math.cos(fp) * Math.cos(fy2);
    let dY = Math.sin(fp);
    let dZ = Math.cos(fp) * Math.sin(fy2);

    this.scene.setCamera({
      position: [eyeX, eyeY, eyeZ],
      target: [eyeX + dX, eyeY + dY, eyeZ + dZ],
      fov: this.currentFov, near: 0.05, far: 500,
    });

    this._eyeX = eyeX; this._eyeY = eyeY; this._eyeZ = eyeZ;
    this._finalYaw = fy2; this._finalPitch = fp;
    this._dirX = dX; this._dirY = dY; this._dirZ = dZ;
    this._groundSpeed = gs; this._moving = moving;
  }

  getStatus() {
    if (!this.onGround) return "airborne";
    if (this.crouching) return "crouching";
    if (this.sprinting && this._groundSpeed > 0.5) return "sprinting";
    if (this._groundSpeed > 0.5) return "walking";
    return "idle";
  }
  getPosition() { return { x: this.x, y: this.y, z: this.z }; }
}

// ═══════════════════════════════════════════════════════════════
//  GunController — reduced shake during jumps
// ═══════════════════════════════════════════════════════════════
class GunController {
  constructor(scene, player, opts) {
    this.scene = scene;
    this.player = player;
    this.offsetRight = opts.offsetRight || 0.25;
    this.offsetDown = opts.offsetDown || -0.2;
    this.offsetForward = opts.offsetForward || 0.5;
    this.swaySmooth = opts.swaySmooth || 6.0;
    this.swayMaxAngle = opts.swayMaxAngle || 0.04;
    this.bobAmountX = opts.bobAmountX || 0.01;
    this.bobAmountY = opts.bobAmountY || 0.008;
    this.currentSwayX = 0; this.currentSwayY = 0;
    this.bobX = 0; this.bobY = 0;
    this.meshName = opts.meshName || "gun";
    this.loaded = false;

    // Smoothed landing dip for the gun (separate from camera)
    this.gunDip = 0;
  }

  update(dt) {
    if (!this.loaded) return;
    let p = this.player;
    let yaw = p._finalYaw;
    let pitch = p._finalPitch;

    // Sway from look delta
    let sx = -(p.targetYaw - p.yaw) * 1.5;
    let sy = (p.targetPitch - p.pitch) * 1.5;
    if (sx > this.swayMaxAngle) sx = this.swayMaxAngle;
    if (sx < -this.swayMaxAngle) sx = -this.swayMaxAngle;
    if (sy > this.swayMaxAngle) sy = this.swayMaxAngle;
    if (sy < -this.swayMaxAngle) sy = -this.swayMaxAngle;
    let t = 1.0 - Math.pow(0.001, dt * this.swaySmooth);
    this.currentSwayX += (sx - this.currentSwayX) * t;
    this.currentSwayY += (sy - this.currentSwayY) * t;

    // Bob — only when grounded and moving
    if (p._moving && p.onGround) {
      this.bobX = Math.cos(p.headBobPhase * 0.5) * this.bobAmountX * p.headBobAmount;
      this.bobY = Math.abs(Math.sin(p.headBobPhase)) * this.bobAmountY * p.headBobAmount;
    } else {
      this.bobX *= 0.85;
      this.bobY *= 0.85;
    }

    // Smooth the landing dip for the gun separately — much gentler than camera
    // Gun gets only 20% of the camera's landing dip, smoothed further
    let targetDip = p.landingDip * 0.2;
    this.gunDip += (targetDip - this.gunDip) * Math.min(1, dt * 6);

    // Camera basis vectors
    let fwdX = Math.cos(pitch) * Math.cos(yaw);
    let fwdY = Math.sin(pitch);
    let fwdZ = Math.cos(pitch) * Math.sin(yaw);
    let rightX = Math.cos(yaw + Math.PI / 2);
    let rightZ = Math.sin(yaw + Math.PI / 2);
    let upX = -rightZ * fwdY;
    let upY = rightZ * fwdX - rightX * fwdZ;
    let upZ = rightX * fwdY;
    let uL = Math.sqrt(upX * upX + upY * upY + upZ * upZ);
    if (uL > 0.001) { upX /= uL; upY /= uL; upZ /= uL; }
    else { upX = 0; upY = 1; upZ = 0; }

    let oR = this.offsetRight + this.currentSwayX + this.bobX;
    let oU = this.offsetDown + this.currentSwayY + this.bobY + this.gunDip;
    let oF = this.offsetForward;

    let ex = p._eyeX, ey = p._eyeY, ez = p._eyeZ;
    let gx = ex + fwdX * oF + rightX * oR + upX * oU;
    let gy = ey + fwdY * oF + upY * oU;
    let gz = ez + fwdZ * oF + rightZ * oR + upZ * oU;

    this.scene.setMeshPosition(this.meshName, gx, gy, gz);
    let lookDist = 10.0;
    this.scene.lookAt(this.meshName, gx - fwdX * lookDist, gy - fwdY * lookDist, gz - fwdZ * lookDist);
  }
}

// ═══════════════════════════════════════════════════════════════
//  Scene builder helpers
// ═══════════════════════════════════════════════════════════════
let meshCounter = 0;

// Standard block: sits on the ground, collision from y to y+h
function addBlock(scene, player, x, y, z, w, h, d, color, matOpts) {
  let name = "block_" + (meshCounter++);
  let mat = matOpts || {};
  mat.color = color;
  if (!mat.type) mat.type = "phong";
  if (!mat.shininess) mat.shininess = 20;

  scene.addMesh(name, "box", {
    width: w, height: h, depth: d,
    position: [x, y + h / 2, z],
    material: mat,
  });

  player.addObstacle(x, z, w / 2, d / 2, y + h, y);
  return name;
}

// Elevated block: collision only between minH and maxH (player can walk under)
function addElevatedBlock(scene, player, x, y, z, w, h, d, color, matOpts) {
  let name = "block_" + (meshCounter++);
  let mat = matOpts || {};
  mat.color = color;
  if (!mat.type) mat.type = "phong";
  if (!mat.shininess) mat.shininess = 20;

  scene.addMesh(name, "box", {
    width: w, height: h, depth: d,
    position: [x, y + h / 2, z],
    material: mat,
  });

  // minH = y (bottom of block), so player can walk under if their head is below y
  player.addObstacle(x, z, w / 2, d / 2, y + h, y);
  return name;
}

function buildScene(scene, player) {
  scene.setAmbient("#ffffff");
  scene.addLight({ type: "directional", direction: [-0.3, -1, -0.5], color: "#fff5e0", intensity: 0.2 });
  scene.addLight({ type: "directional", direction: [0.5, -0.3, 0.8], color: "#c0d0ff", intensity: 0.3 });

  // Sky
  scene.addMesh("sky", "sphere", {
    radius: 190, position: [0, 0, 0],
    material: { type: "basic", color: "#6BAED6", side: "double" },
  });

  // Ground
  scene.addMesh("ground", "box", {
    width: 400, height: 0.05, depth: 400, position: [0, 0, 0],
    material: { type: "phong", color: "#5A8F6A", shininess: 8 },
  });

  // Scattered crates near spawn
  addBlock(scene, player, 3, 0, 2, 1, 1, 1, "#8B6914");
  addBlock(scene, player, 4.5, 0, 1.5, 0.8, 0.8, 0.8, "#9B7924");
  addBlock(scene, player, 3.5, 1, 2, 0.6, 0.6, 0.6, "#AB8934");
  addBlock(scene, player, -2, 0, 3, 1.2, 0.6, 1.2, "#7B5904");

  // Stepping stones / parkour path
  addBlock(scene, player, 6, 0, -2, 1.5, 0.4, 1.5, "#887766");
  addBlock(scene, player, 8.5, 0.5, -3, 1.2, 0.5, 1.2, "#887766");
  addBlock(scene, player, 11, 1.0, -2.5, 1.0, 0.4, 1.0, "#887766");
  addBlock(scene, player, 13, 1.6, -1.5, 1.2, 0.4, 1.2, "#887766");
  addBlock(scene, player, 15, 2.2, -2, 1.0, 0.4, 1.0, "#887766");
  addBlock(scene, player, 17, 2.8, -1, 1.5, 0.5, 1.5, "#887766");

  // Large platform
  addBlock(scene, player, 20, 2.8, 0, 6, 0.3, 6, "#556655");

  // Watchtower on platform
  addBlock(scene, player, 22, 3.1, 2, 1.2, 3, 1.2, "#665544");
  addBlock(scene, player, 22, 6.1, 2, 2.5, 0.3, 2.5, "#776655");
  addBlock(scene, player, 22, 6.4, 3.1, 2.5, 1.0, 0.2, "#665544");
  addBlock(scene, player, 22, 6.4, 0.9, 2.5, 1.0, 0.2, "#665544");
  addBlock(scene, player, 23.1, 6.4, 2, 0.2, 1.0, 2.5, "#665544");
  addBlock(scene, player, 20.9, 6.4, 2, 0.2, 1.0, 2.5, "#665544");

  // ═════════════════════════════════════════════════════════════
  //  CUBE CASTLE — centered at (-15, 0, -15)
  // ═════════════════════════════════════════════════════════════
  let cx = -15, cz = -15;
  let stone = "#888888";
  let stoneD = "#777777";
  let stoneL = "#999999";
  let wood = "#6B4226";

  // Castle floor
  addBlock(scene, player, cx, 0, cz, 16, 0.4, 16, stoneD);

  // Four corner towers
  let towerPositions = [
    [cx - 7, cz - 7], [cx + 7, cz - 7],
    [cx - 7, cz + 7], [cx + 7, cz + 7],
  ];
  for (let i = 0; i < towerPositions.length; i++) {
    let tx = towerPositions[i][0];
    let tz = towerPositions[i][1];
    addBlock(scene, player, tx, 0.4, tz, 3, 5, 3, stone);
    addBlock(scene, player, tx, 5.4, tz, 3.6, 0.3, 3.6, stoneL);
    addBlock(scene, player, tx - 1.2, 5.7, tz, 0.6, 0.8, 0.6, stone);
    addBlock(scene, player, tx + 1.2, 5.7, tz, 0.6, 0.8, 0.6, stone);
    addBlock(scene, player, tx, 5.7, tz - 1.2, 0.6, 0.8, 0.6, stone);
    addBlock(scene, player, tx, 5.7, tz + 1.2, 0.6, 0.8, 0.6, stone);
  }

  // Front wall with gate
  // Left wall section (from left tower to gate)
  addBlock(scene, player, cx - 4, 0.4, cz - 7, 3, 4, 1.0, stone);
  // Right wall section (from gate to right tower)
  addBlock(scene, player, cx + 4, 0.4, cz - 7, 3, 4, 1.0, stone);
  // Gate arch — ELEVATED so player walks under it (bottom at 2.5m, player is 1.7m)
  addElevatedBlock(scene, player, cx, 2.8, cz - 7, 5, 1.6, 1.0, stone);
  // Gate pillars (the sides of the gate opening, only up to arch height)
  addBlock(scene, player, cx - 2.2, 0.4, cz - 7, 0.6, 2.4, 1.0, stoneD);
  addBlock(scene, player, cx + 2.2, 0.4, cz - 7, 0.6, 2.4, 1.0, stoneD);
  // Wall top walkway (front)
  addBlock(scene, player, cx, 4.4, cz - 7, 11, 0.3, 1.2, stoneL);

  // Back wall
  addBlock(scene, player, cx, 0.4, cz + 7, 11, 4, 1.0, stone);
  addBlock(scene, player, cx, 4.4, cz + 7, 11, 0.3, 1.2, stoneL);

  // Left wall
  addBlock(scene, player, cx - 7, 0.4, cz, 1.0, 4, 11, stone);
  addBlock(scene, player, cx - 7, 4.4, cz, 1.2, 0.3, 11, stoneL);

  // Right wall
  addBlock(scene, player, cx + 7, 0.4, cz, 1.0, 4, 11, stone);
  addBlock(scene, player, cx + 7, 4.4, cz, 1.2, 0.3, 11, stoneL);

  // Battlements along wall tops
  for (let m = -4; m <= 4; m += 2) {
    addBlock(scene, player, cx + m, 4.7, cz - 7, 0.6, 0.7, 0.4, stone);
    addBlock(scene, player, cx + m, 4.7, cz + 7, 0.6, 0.7, 0.4, stone);
    addBlock(scene, player, cx - 7, 4.7, cz + m, 0.4, 0.7, 0.6, stone);
    addBlock(scene, player, cx + 7, 4.7, cz + m, 0.4, 0.7, 0.6, stone);
  }

  // Inner keep
  addBlock(scene, player, cx, 0.4, cz, 5, 3.5, 5, stoneD);
  addBlock(scene, player, cx, 3.9, cz, 5.5, 0.3, 5.5, stoneL);

  // Stairs: courtyard to wall walkway (inside left wall)
  let stairX = cx - 5.5;
  let stairZ = cz - 3;
  for (let s = 0; s < 8; s++) {
    addBlock(scene, player, stairX, 0.4 + s * 0.5, stairZ + s * 0.7, 1.5, 0.5, 0.7, wood);
  }

  // Stairs: courtyard to keep top (back side)
  let keepStairX = cx + 1;
  let keepStairZ = cz + 2;
  for (let s = 0; s < 7; s++) {
    addBlock(scene, player, keepStairX + s * 0.6, 0.4 + s * 0.5, keepStairZ, 0.6, 0.5, 1.2, wood);
  }

  // Courtyard crates
  addBlock(scene, player, cx + 3, 0.4, cz - 3, 0.8, 0.8, 0.8, "#7B5530");
  addBlock(scene, player, cx + 3.5, 0.4, cz - 4, 0.6, 0.6, 0.6, "#6B4520");
  addBlock(scene, player, cx + 3, 1.2, cz - 3, 0.5, 0.5, 0.5, "#8B6540");

  // Barrels
  addBlock(scene, player, cx - 3, 0.4, cz + 3, 0.8, 1.0, 0.8, "#5B3510");
  addBlock(scene, player, cx - 4, 0.4, cz + 3.5, 0.8, 1.0, 0.8, "#5B3510");

  // Ruins outside castle
  addBlock(scene, player, cx + 12, 0, cz - 5, 2, 1.5, 2, "#777777");
  addBlock(scene, player, cx + 13, 0, cz - 4, 1.5, 0.8, 1.0, "#888888");
  addBlock(scene, player, cx - 10, 0, cz + 10, 3, 0.6, 2, "#777777");
  addBlock(scene, player, cx + 5, 0, cz + 12, 1.5, 2.0, 1.5, "#888888");

  // Spiral climb
  addBlock(scene, player, 0, 0, -10, 2, 1.0, 2, "#667766");
  addBlock(scene, player, 1.5, 1.0, -11, 1.5, 1.0, 1.5, "#667766");
  addBlock(scene, player, 0, 2.0, -12, 1.5, 1.0, 1.5, "#667766");
  addBlock(scene, player, -1.5, 3.0, -11, 1.5, 1.0, 1.5, "#667766");
  addBlock(scene, player, 0, 4.0, -10, 2, 0.3, 2, "#778877");
}

// ═══════════════════════════════════════════════════════════════
//  Placeholder gun + OBJ loader
// ═══════════════════════════════════════════════════════════════
function createPlaceholderGun(scene) {
  scene.addGroup("gun_vm");
  scene.addMesh("gun_body", "box", {
    width: 0.06, height: 0.06, depth: 0.4,
    material: { type: "phong", color: "#555555", shininess: 64, specular: "#888888" },
    parent: "gun_vm",
  });
  scene.addMesh("gun_barrel", "cylinder", {
    radius: 0.018, height: 0.22, position: [0, 0.015, -0.28],
    material: { type: "phong", color: "#444444", shininess: 96, specular: "#aaaaaa" },
    parent: "gun_vm",
  });
  scene.addMesh("gun_grip", "box", {
    width: 0.04, height: 0.1, depth: 0.04, position: [0, -0.07, 0.06],
    material: { type: "phong", color: "#333333", shininess: 32 },
    parent: "gun_vm",
  });
  return "gun_vm";
}

function loadGun(scene) {
  let GUN_OBJ_PATH = "examples/call_of_sunflower/models/M4A1.obj";
  let gunScale = 0.018;
  scene.loadOBJ("m4a1", GUN_OBJ_PATH, {
    color: "#aaaaaa",
    material: { type: "phong", color: "#aaaaaa", shininess: 80, specular: "#cccccc" },
    scale: [gunScale, gunScale, gunScale],
    position: [0, -100, 0],
  });
  let children = scene.getObjectChildren("m4a1");
  return { meshName: "m4a1", loaded: children.length > 0 };
}

// ═══════════════════════════════════════════════════════════════
//  HUD — hex colors only
// ═══════════════════════════════════════════════════════════════
function drawHUD(ctx, scene, player, gunStatus) {
  let w = scene.getWidth();
  let h = scene.getHeight();
  let cx = w / 2;
  let cy = h / 2;

  let spread = 3 + player._groundSpeed * 0.8;
  let inner = spread;
  let outer = inner + 6;

  ctx.drawLine(cx - outer, cy + 1, cx - inner, cy + 1, "#00000066", 2);
  ctx.drawLine(cx + inner, cy + 1, cx + outer, cy + 1, "#00000066", 2);
  ctx.drawLine(cx + 1, cy - outer, cx + 1, cy - inner, "#00000066", 2);
  ctx.drawLine(cx + 1, cy + inner, cx + 1, cy + outer, "#00000066", 2);

  ctx.drawLine(cx - outer, cy, cx - inner, cy, "#ccddbb", 1.5);
  ctx.drawLine(cx + inner, cy, cx + outer, cy, "#ccddbb", 1.5);
  ctx.drawLine(cx, cy - outer, cx, cy - inner, "#ccddbb", 1.5);
  ctx.drawLine(cx, cy + inner, cx, cy + outer, "#ccddbb", 1.5);

  ctx.fillCircle(cx, cy, 1.2, "#ffffffcc");

  let status = player.getStatus();
  let statusColors = {
    idle: "#8899aa", walking: "#aaccaa", sprinting: "#ffcc44",
    airborne: "#77bbff", crouching: "#bb99dd",
  };
  let statusLabels = {
    idle: "IDLE", walking: "WALKING", sprinting: "SPRINTING",
    airborne: "AIRBORNE", crouching: "CROUCHING",
  };
  let sCol = statusColors[status] || "#888888";
  let sLabel = statusLabels[status] || "---";

  let barW = 130, barH = 20;
  let barX = cx - barW / 2;
  let barY = h - 56;
  ctx.fillRect(barX, barY, barW, barH, "#0000004d");
  ctx.fillText(sLabel, barX + 10, barY + 14, sCol, 12);

  let speedMax = player.moveSpeed * player.sprintMultiplier;
  let speedRatio = Math.min(player._groundSpeed / speedMax, 1.0);
  let sBarW = barW - 8;
  let sBarY = barY + barH + 3;
  ctx.fillRect(barX + 4, sBarY, sBarW, 3, "#00000040");
  if (speedRatio > 0.01) {
    ctx.fillRect(barX + 4, sBarY, sBarW * speedRatio, 3, sCol);
  }

  ctx.fillText("WASD move | Mouse look | Space jump | Shift sprint", 12, 18, "#aabbcc99", 10);

  if (gunStatus) {
    let isLoaded = gunStatus.indexOf("loaded") >= 0;
    let gCol = isLoaded ? "#88ff88b3" : "#ffaa64b3";
    let textW = gunStatus.length * 6;
    ctx.fillText(gunStatus, w - textW - 14, 18, gCol, 10);
  }

  let stats = scene.getStats();
  let fps = stats.frameMs > 0 ? Math.round(1000.0 / stats.frameMs) : 0;
  let fpsCol = "#66778899";
  if (fps < 50) fpsCol = "#ccaa3299";
  if (fps < 30) fpsCol = "#cc5050b3";
  ctx.fillText(fps + " fps", 12, h - 28, fpsCol, 10);
  ctx.fillText(stats.triangles + " tris", 12, h - 14, "#66778873", 9);

  let pos = player.getPosition();
  let posStr = pos.x.toFixed(1) + ", " + pos.y.toFixed(1) + ", " + pos.z.toFixed(1);
  let posW = posStr.length * 5.5;
  ctx.fillText(posStr, w - posW - 14, h - 14, "#66778873", 9);
}

// ═══════════════════════════════════════════════════════════════
//  Main
// ═══════════════════════════════════════════════════════════════
function Game() {
  useEffect(function () {
    let scene = new Canvas3D("viewport", { width: 800, height: 600, framesPerSecond: 60 });
    let keys = new KeyState(scene);

    let player = new FirstPersonController(scene, keys, {
      x: 0, z: 5, eyeHeight: 1.7, yaw: -Math.PI / 2,
      moveSpeed: 5.0, sprintMultiplier: 1.8,
      acceleration: 40.0, friction: 12.0,
      airFriction: 2.0, airControl: 0.3,
      jumpForce: 7.0, gravity: -20.0,
      fov: 70, sprintFov: 82,
      playerHeight: 1.7,
      bounds: { minX: -198, maxX: 198, minZ: -198, maxZ: 198 },
    });

    buildScene(scene, player);

    let placeholderName = createPlaceholderGun(scene);
    let objResult = loadGun(scene);
    let gunStatus = "";
    let activeMesh;

    if (objResult.loaded) {
      activeMesh = objResult.meshName;
      scene.setMeshVisible(placeholderName, false);
      gunStatus = "M4A1.obj loaded";
    } else {
      activeMesh = placeholderName;
      scene.removeMesh(objResult.meshName);
      gunStatus = "OBJ not found - placeholder";
    }

    let gun = new GunController(scene, player, {
      meshName: activeMesh,
      offsetRight: 0.06, offsetDown: -0.10, offsetForward: 0.22,
      swaySmooth: 6.0, swayMaxAngle: 0.03,
      bobAmountX: 0.004, bobAmountY: 0.003,
    });
    gun.loaded = true;

    scene.onUpdate(function (dt) {
      player.update(dt);
      gun.update(dt);
    });

    scene.onDraw(function (ctx) {
      drawHUD(ctx, scene, player, gunStatus);
    });

    scene.start();
  }, []);

  return (
    <Box orientation="vertical" expand={true}>
      <Canvas id="viewport" expand={true} />
    </Box>
  );
}

function App() { return <Game />; }

$.onReady(function () {
  $.render("root", App);
});