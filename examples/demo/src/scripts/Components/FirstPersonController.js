import { Vector3, Input, Camera } from "tachyon";

class FirstPersonController {
  constructor(opts) {
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
  }

  addObstacle(x, z, halfW, halfD, height, minH) {
    this.obstacles.push({
      x: x, z: z, halfW: halfW, halfD: halfD,
      height: height, minH: minH || 0,
    });
  }

  addViewPunch(p, y) { this.viewPunchPitch += p; this.viewPunchYaw += y; }

  updateMouse() {
    let mouse = Input.mouseDelta();
    this.mouseDeltaX += mouse.x;
    this.mouseDeltaY += mouse.y;
  }

  _collidesAt(nx, nz, feetY) {
    let r = this.playerRadius;
    let headY = feetY + this.playerHeight;
    for (let i = 0; i < this.obstacles.length; i++) {
      let ob = this.obstacles[i];
      if (feetY >= ob.height - this.stepHeight) continue;
      if (headY <= ob.minH) continue;
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

    this.updateMouse();

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
    this.sprinting = Input.keyDown("Shift_L") || Input.keyDown("Shift_R");
    this.crouching = Input.keyDown("Control_L") || Input.keyDown("Control_R") || Input.keyDown("C");
    let targetEye = this.crouching ? this.crouchHeight : this.standHeight;
    this.currentEyeHeight += (targetEye - this.currentEyeHeight) * Math.min(1, dt * 12);
    let maxSpeed = this.moveSpeed * (this.sprinting ? this.sprintMultiplier : 1.0);
    if (this.crouching) maxSpeed *= 0.5;

    // Movement
    let fX = Math.cos(this.yaw), fZ = Math.sin(this.yaw);
    let rX = Math.cos(this.yaw + Math.PI / 2), rZ = Math.sin(this.yaw + Math.PI / 2);
    let wX = 0, wZ = 0;
    if (Input.keyDown("W")) { wX += fX; wZ += fZ; }
    if (Input.keyDown("S")) { wX -= fX; wZ -= fZ; }
    if (Input.keyDown("A")) { wX -= rX; wZ -= rZ; }
    if (Input.keyDown("D")) { wX += rX; wZ += rZ; }
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
    if (Input.keyDown("Space")) this.jumpBufferTimer = this.jumpBuffer; else this.jumpBufferTimer -= dt;
    if (this.jumpBufferTimer > 0 && this.groundTimer > 0) {
      this.velY = this.jumpForce; this.onGround = false;
      this.groundTimer = 0; this.jumpBufferTimer = 0; this.fallStartY = this.y;
    }

    // Gravity
    if (!this.onGround) this.velY += this.gravity * dt;
    this.y += this.velY * dt;

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

    // Landing dip
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

    Camera.setPosition(new Vector3(eyeX, eyeY, eyeZ));
    Camera.setTarget(new Vector3(eyeX + dX, eyeY + dY, eyeZ + dZ));
    Camera.setFOV(this.currentFov);

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

export default FirstPersonController;