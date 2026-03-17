import { Canvas, Canvas3D } from "canvas";

class FirstPersonController {
  constructor(scene, opts) {
    this.scene = scene;
    this.x = opts.x || 0;
    this.y = opts.eyeHeight || 1.7;
    this.z = opts.z || 0;
    this.eyeHeight = opts.eyeHeight || 1.7;
    this.yaw = opts.yaw || 0;
    this.pitch = opts.pitch || 0;

    this.moveSpeed = opts.moveSpeed || 4.0;
    this.sprintMultiplier = opts.sprintMultiplier || 2.0;
    this.mouseSensitivity = opts.mouseSensitivity || 0.003;
    this.jumpForce = opts.jumpForce || 6.0;
    this.gravity = opts.gravity || -15.0;

    this.velY = 0;
    this.onGround = true;
    this.playerRadius = opts.playerRadius || 0.35;
    this.obstacles = [];
    this.bounds = opts.bounds || { minX: -50, maxX: 50, minZ: -50, maxZ: 50 };

    this.lastMouseX = -1;
    this.lastMouseY = -1;
    this.headBob = 0;
    this.sprinting = false;

    this._bindInput();
  }

  addObstacle(x, z, halfW, halfD, height) {
    this.obstacles.push({ x, z, halfW, halfD, height });
  }

  _bindInput() {
    let self = this;
    this.scene.onMouseMove(function (mx, my) {
      if (self.lastMouseX < 0) {
        self.lastMouseX = mx;
        self.lastMouseY = my;
        return;
      }
      let dx = mx - self.lastMouseX;
      let dy = my - self.lastMouseY;
      self.lastMouseX = mx;
      self.lastMouseY = my;

      self.yaw += dx * self.mouseSensitivity;
      self.pitch -= dy * self.mouseSensitivity;
      if (self.pitch > 1.45) self.pitch = 1.45;
      if (self.pitch < -1.45) self.pitch = -1.45;
    });
  }

  _collides(nx, nz) {
    let feetY = this.y - this.eyeHeight;
    for (let i = 0; i < this.obstacles.length; i++) {
      let ob = this.obstacles[i];
      if (feetY >= ob.height) continue;
      let cx = Math.max(ob.x - ob.halfW, Math.min(nx, ob.x + ob.halfW));
      let cz = Math.max(ob.z - ob.halfD, Math.min(nz, ob.z + ob.halfD));
      let dx = nx - cx;
      let dz = nz - cz;
      if (dx * dx + dz * dz < this.playerRadius * this.playerRadius) return true;
    }
    return false;
  }

  _tryMove(nx, nz) {
    if (!this._collides(nx, nz)) { this.x = nx; this.z = nz; return; }
    if (!this._collides(nx, this.z)) { this.x = nx; return; }
    if (!this._collides(this.x, nz)) { this.z = nz; return; }
  }

  update(dt) {
    let s = this.scene;
    this.sprinting = s.isKeyDown("Shift_L") || s.isKeyDown("Shift_R");
    let speed = this.moveSpeed * dt * (this.sprinting ? this.sprintMultiplier : 1.0);

    let flatX = Math.cos(this.yaw);
    let flatZ = Math.sin(this.yaw);
    let rightX = Math.cos(this.yaw + Math.PI / 2);
    let rightZ = Math.sin(this.yaw + Math.PI / 2);

    let mx = 0, mz = 0;
    if (s.isKeyDown("W")) { mx += flatX * speed; mz += flatZ * speed; }
    if (s.isKeyDown("S")) { mx -= flatX * speed; mz -= flatZ * speed; }
    if (s.isKeyDown("A")) { mx -= rightX * speed; mz -= rightZ * speed; }
    if (s.isKeyDown("D")) { mx += rightX * speed; mz += rightZ * speed; }

    let len = Math.sqrt(mx * mx + mz * mz);
    if (len > speed && len > 0) { mx = mx / len * speed; mz = mz / len * speed; }

    this._tryMove(this.x + mx, this.z + mz);

    let b = this.bounds;
    if (this.x < b.minX) this.x = b.minX;
    if (this.x > b.maxX) this.x = b.maxX;
    if (this.z < b.minZ) this.z = b.minZ;
    if (this.z > b.maxZ) this.z = b.maxZ;

    if (s.isKeyDown("Space") && this.onGround) {
      this.velY = this.jumpForce;
      this.onGround = false;
    }

    this.velY += this.gravity * dt;
    this.y += this.velY * dt;

    if (this.y <= this.eyeHeight) {
      this.y = this.eyeHeight;
      this.velY = 0;
      this.onGround = true;
    }

    let moving = len > 0.001 && this.onGround;
    if (moving) {
      let bobSpeed = this.sprinting ? 14.0 : 9.0;
      let bobAmp = this.sprinting ? 0.06 : 0.035;
      this.headBob += dt * bobSpeed;
      var bobOffset = Math.sin(this.headBob) * bobAmp;
    } else {
      this.headBob *= 0.85;
      var bobOffset = Math.sin(this.headBob) * 0.01;
    }

    let eyeY = this.y + bobOffset;
    let dirX = Math.cos(this.pitch) * Math.cos(this.yaw);
    let dirY = Math.sin(this.pitch);
    let dirZ = Math.cos(this.pitch) * Math.sin(this.yaw);

    s.setCamera({
      position: [this.x, eyeY, this.z],
      target: [this.x + dirX, eyeY + dirY, this.z + dirZ],
      fov: this.sprinting ? 75 : 65,
      near: 0.1,
      far: 200,
    });
  }

  getStatus() {
    if (!this.onGround) return "airborne";
    if (this.sprinting) return "sprinting";
    return "walking";
  }
}

function buildScene(scene) {
  scene.setAmbient("#1a1a2a");

  scene.addLight({ type: "directional", direction: [-0.4, -0.8, -0.3], color: "#ffeedd", intensity: 0.9 });
  scene.addLight({ type: "point", position: [0, 4, 0], color: "#ffcc66", intensity: 1.2 });
  scene.addLight({ type: "point", position: [-8, 3, -8], color: "#4488ff", intensity: 0.7 });
  scene.addLight({ type: "point", position: [8, 3, 8], color: "#ff4466", intensity: 0.7 });

  scene.addMesh("ground", "plane", {
    width: 40, depth: 40,
    material: { type: "lambert", color: "#3a3a4a", ambient: "#222233" },
  });

  scene.addGridHelper(40, 40);
  scene.addAxesHelper(2);

  scene.addGroup("city");

  let buildings = [
    { name: "tower1", x: 0, z: 0, w: 1.2, d: 1.2, h: 4, color: "#5577aa" },
    { name: "tower2", x: 5, z: -3, w: 1.5, d: 1.5, h: 6, color: "#aa5555" },
    { name: "tower3", x: -4, z: 2, w: 1, d: 1, h: 3, color: "#55aa77" },
    { name: "tower4", x: -3, z: -7, w: 2, d: 2, h: 8, color: "#cc8833" },
    { name: "tower5", x: 7, z: 5, w: 0.8, d: 0.8, h: 5, color: "#7755cc" },
    { name: "wide1", x: -8, z: -2, w: 3, d: 1.5, h: 2.5, color: "#557799" },
    { name: "wide2", x: 3, z: 8, w: 2, d: 3, h: 2, color: "#886644" },
    { name: "slab1", x: 10, z: -6, w: 1, d: 4, h: 3, color: "#669966" },
  ];

  let obstacles = [];
  for (let i = 0; i < buildings.length; i++) {
    let b = buildings[i];
    scene.addMesh(b.name, "box", {
      width: b.w, height: b.h, depth: b.d,
      position: [b.x, b.h / 2, b.z],
      material: { type: "phong", color: b.color, shininess: 16, specular: "#444444" },
      parent: "city",
    });
    scene.addMesh(b.name + "_cap", "box", {
      width: b.w + 0.15, height: 0.15, depth: b.d + 0.15,
      position: [b.x, b.h + 0.075, b.z],
      material: { type: "phong", color: "#eeeeee", shininess: 48 },
      parent: "city",
    });
    obstacles.push({ x: b.x, z: b.z, halfW: b.w / 2 + 0.1, halfD: b.d / 2 + 0.1, height: b.h });
  }

  scene.addMesh("pillar_a", "cylinder", {
    radius: 0.25, height: 4, position: [-6, 2, 5],
    material: { type: "phong", color: "#cc9966", shininess: 32, specular: "#ffddaa" },
  });
  obstacles.push({ x: -6, z: 5, halfW: 0.35, halfD: 0.35, height: 4 });

  scene.addMesh("pillar_b", "cylinder", {
    radius: 0.25, height: 4, position: [-4, 2, 5],
    material: { type: "phong", color: "#cc9966", shininess: 32, specular: "#ffddaa" },
  });
  obstacles.push({ x: -4, z: 5, halfW: 0.35, halfD: 0.35, height: 4 });

  scene.addMesh("pillar_beam", "box", {
    width: 2.5, height: 0.2, depth: 0.5, position: [-5, 4.1, 5],
    material: { type: "phong", color: "#ddbb88", shininess: 24 },
  });

  scene.addMesh("deco_sphere", "sphere", {
    radius: 0.6, position: [0, 4.6, 0],
    material: { type: "phong", color: "#ffcc33", shininess: 128, specular: "#ffffff" },
  });

  scene.addMesh("deco_torus", "torus", {
    radius: 1.2, tube: 0.15, position: [0, 5.5, 0],
    material: { type: "phong", color: "#ff6644", shininess: 64, specular: "#ffffff" },
  });

  scene.addMesh("deco_ring", "ring", {
    innerRadius: 0.8, outerRadius: 1.1, position: [0, 6.5, 0],
    material: { type: "phong", color: "#44aaff", shininess: 96, specular: "#ffffff", side: "double" },
  });

  scene.addMesh("knot", "torusKnot", {
    radius: 0.5, tube: 0.15, position: [8, 1.5, -1],
    material: { type: "phong", color: "#cc55ff", shininess: 80, specular: "#ffffff" },
  });
  obstacles.push({ x: 8, z: -1, halfW: 0.8, halfD: 0.8, height: 2.5 });

  scene.addMesh("icosa", "icosahedron", {
    radius: 0.7, position: [-10, 0.7, -5],
    material: { type: "phong", color: "#33ddaa", shininess: 48 },
  });
  obstacles.push({ x: -10, z: -5, halfW: 0.8, halfD: 0.8, height: 1.4 });

  scene.addMesh("cone_marker", "cone", {
    radius: 0.4, height: 1.2, position: [12, 0.6, 3],
    material: { type: "phong", color: "#ff8800", shininess: 32 },
  });

  scene.addMesh("glass_box", "box", {
    width: 3, height: 2, depth: 3, position: [-7, 1, -10],
    material: { type: "phong", color: "#88ccff", shininess: 128, specular: "#ffffff", transparent: true, opacity: 0.3, side: "double" },
  });

  scene.addMesh("glass_inner", "sphere", {
    radius: 0.5, position: [-7, 1, -10],
    material: { type: "phong", color: "#ff3366", shininess: 96 },
  });

  scene.addMesh("lamp_post", "cylinder", {
    radius: 0.08, height: 3, position: [6, 1.5, -8],
    material: { type: "basic", color: "#333333" },
  });
  scene.addLight({ type: "point", position: [6, 3.2, -8], color: "#ffeeaa", intensity: 1.5 });
  scene.addMesh("lamp_bulb", "sphere", {
    radius: 0.15, position: [6, 3.2, -8],
    material: { type: "basic", color: "#ffffcc" },
  });

  scene.setFog({ type: "linear", color: "#0d0d1a", near: 20, far: 60 });

  return obstacles;
}

function Game() {
  useEffect(function () {
    const scene = new Canvas3D("viewport", {
      width: 800,
      height: 600,
      framesPerSecond: 60,
    });

    let obstacleList = buildScene(scene);

    let player = new FirstPersonController(scene, {
      x: 0, z: 10, eyeHeight: 1.7,
      yaw: -Math.PI / 2,
      moveSpeed: 4.5,
      sprintMultiplier: 2.2,
      jumpForce: 6.5,
      gravity: -16.0,
      bounds: { minX: -18, maxX: 18, minZ: -18, maxZ: 18 },
    });

    for (let i = 0; i < obstacleList.length; i++) {
      let ob = obstacleList[i];
      player.addObstacle(ob.x, ob.z, ob.halfW, ob.halfD, ob.height);
    }

    let time = 0;
    let lookTarget = "";

    scene.onKeyDown(function (key) {
      if (key === "E") {
        let mx = scene.mouseX();
        let my = scene.mouseY();
        let hits = scene.raycast(mx, my);
        if (hits.length > 0) {
          lookTarget = hits[0].name + " (d:" + hits[0].distance.toFixed(1) + ")";
        } else {
          lookTarget = "";
        }
      }
    });

    scene.onUpdate(function (dt) {
      time += dt;
      player.update(dt);

      scene.rotateMesh("deco_torus", 0, dt * 0.6, dt * 0.3);
      scene.rotateMesh("deco_ring", dt * 0.4, 0, dt * 0.7);
      scene.rotateMesh("knot", dt * 0.3, dt * 0.5, 0);
      scene.rotateMesh("icosa", dt * 0.2, dt * 0.4, dt * 0.1);

      let sphereY = 4.6 + Math.sin(time * 1.2) * 0.4;
      scene.setMeshPosition("deco_sphere", 0, sphereY, 0);

      let coneY = 0.6 + Math.abs(Math.sin(time * 2.0)) * 0.3;
      scene.setMeshPosition("cone_marker", 12, coneY, 3);
      scene.rotateMesh("cone_marker", 0, dt * 2.0, 0);

      let glassInnerY = 1 + Math.sin(time * 0.8) * 0.3;
      scene.setMeshPosition("glass_inner", -7, glassInnerY, -10);
      scene.rotateMesh("glass_inner", dt * 0.5, dt * 0.7, 0);
    });

    scene.onDraw(function (ctx) {
      ctx.clear("#0d0d1a");

      let status = player.getStatus();
      let statusColors = { walking: "#88aa88", sprinting: "#ffaa22", airborne: "#6688cc" };

      ctx.fillText("WASD move | Mouse look | Space jump | Shift sprint | E inspect", 12, 22, "#7777aa", 13);
      ctx.fillText(status.toUpperCase(), 12, 42, statusColors[status] || "#888888", 12);

      if (lookTarget) {
        ctx.fillText("Target: " + lookTarget, 12, 62, "#ccaa44", 12);
      }

      ctx.fillText("+", scene.getWidth() / 2 - 3, scene.getHeight() / 2 - 6, "#ffffff", 16);

      let stats = scene.getStats();
      let fps = stats.frameMs > 0 ? Math.round(1000.0 / stats.frameMs) : 0;
      ctx.fillText(
        "fps:" + fps + " draw:" + stats.drawCalls + " tri:" + stats.triangles + " cull:" + stats.culled,
        12, scene.getHeight() - 16, "#444466", 11
      );
      ctx.fillText(
        "pos: " + player.x.toFixed(1) + ", " + player.y.toFixed(1) + ", " + player.z.toFixed(1),
        12, scene.getHeight() - 32, "#444466", 11
      );
    });

    scene.start();
  }, []);

  return (
    <Box orientation="vertical" expand={true}>
      <Canvas id="viewport" expand={true} />
    </Box>
  );
}

function App() {
  return <Game />;
}

$.onReady(function () {
  $.render("root", App);
});