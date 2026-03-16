import { Canvas, Canvas3D } from "canvas";

function Game() {
  useEffect(function () {
    const scene = new Canvas3D("cube", { width: 800, height: 600, framesPerSecond: 60 });

    // Camera state
    let camX = 0, camY = 2, camZ = 8;
    let yaw = -Math.PI / 2;
    let pitch = -0.3;
    let lastMouseX = -1, lastMouseY = -1;

    // Movement
    let moveSpeed = 3.0;
    let sprintMultiplier = 2.0;
    let mouseSensitivity = 0.003;

    // Jump / gravity
    let velY = 0;
    let gravity = -12.0;
    let jumpForce = 5.5;
    let onGround = true;
    let groundY = 2.0; // eye height above floor

    // Collision objects: { x, z, halfW, halfD, height }
    let obstacles = [
      { x: 2, z: 0, halfW: 0.6, halfD: 0.6, height: 1.0 },
      { x: 4, z: -2, halfW: 0.85, halfD: 0.85, height: 1.5 },
      { x: -3, z: 1, halfW: 0.5, halfD: 0.5, height: 0.8 },
      { x: -2, z: -5, halfW: 1.1, halfD: 1.1, height: 2.0 },
      { x: 3, z: 3, halfW: 0.4, halfD: 0.4, height: 3.0 },
    ];

    let playerRadius = 0.6;

    scene.setCamera({ position: [camX, camY, camZ], target: [0, 0, 0], fov: 60 });
    scene.addLight({ type: "directional", direction: [-0.5, -1, -0.5], color: "#ffffff", intensity: 1.0 });
    scene.addLight({ type: "point", position: [3, 3, 3], color: "#ff8844", intensity: 0.8 });
    scene.setAmbient("#222233");

    scene.addMesh("floor", "plane", { width: 20, depth: 20, color: "#445566" });
    scene.addMesh("cube1", "cube", { size: 1, color: "#3388ff", position: [0, 0.5, 0] });
    scene.addMesh("cube2", "cube", { size: 1.5, color: "#ff5533", position: [4, 0.75, -2] });
    scene.addMesh("cube3", "cube", { size: 0.8, color: "#33ff88", position: [-3, 0.4, 1] });
    scene.addMesh("cube4", "cube", { size: 2, color: "#ffaa22", position: [-2, 1, -5] });
    scene.addMesh("pillar", "cylinder", { radius: 0.3, height: 3, color: "#8866aa", position: [3, 1.5, 3] });

    function collides(newX, newZ) {
      let feetY = camY - groundY; // player's feet Y position

      for (let i = 0; i < obstacles.length; i++) {
        let ob = obstacles[i];

        // Skip if player's feet are above the obstacle
        if (feetY >= ob.height) continue;

        // AABB vs circle
        let closestX = Math.max(ob.x - ob.halfW, Math.min(newX, ob.x + ob.halfW));
        let closestZ = Math.max(ob.z - ob.halfD, Math.min(newZ, ob.z + ob.halfD));

        let dx = newX - closestX;
        let dz = newZ - closestZ;
        let distSq = dx * dx + dz * dz;

        if (distSq < playerRadius * playerRadius) {
          return true;
        }
      }
      return false;
    }

    function tryMove(newX, newZ) {
      // Try full move
      if (!collides(newX, newZ)) {
        camX = newX;
        camZ = newZ;
        return;
      }

      // Slide along X axis
      if (!collides(newX, camZ)) {
        camX = newX;
        return;
      }

      // Slide along Z axis
      if (!collides(camX, newZ)) {
        camZ = newZ;
        return;
      }

      // Fully blocked
    }

    scene.onMouseMove(function (x, y) {
      if (lastMouseX < 0) { lastMouseX = x; lastMouseY = y; return; }

      let dx = x - lastMouseX;
      let dy = y - lastMouseY;
      lastMouseX = x;
      lastMouseY = y;

      yaw += dx * mouseSensitivity;
      pitch -= dy * mouseSensitivity;

      if (pitch > 1.4) pitch = 1.4;
      if (pitch < -1.4) pitch = -1.4;
    });

    scene.onUpdate(function (dt) {
      let dirX = Math.cos(pitch) * Math.cos(yaw);
      let dirY = Math.sin(pitch);
      let dirZ = Math.cos(pitch) * Math.sin(yaw);

      // Flat forward/right for movement (no vertical component)
      let flatDirX = Math.cos(yaw);
      let flatDirZ = Math.sin(yaw);
      let rightX = Math.cos(yaw + Math.PI / 2);
      let rightZ = Math.sin(yaw + Math.PI / 2);

      // Sprint
      let sprinting = scene.isKeyDown("Shift_L") || scene.isKeyDown("Shift_R");
      let speed = moveSpeed * dt * (sprinting ? sprintMultiplier : 1.0);

      // Accumulate desired move
      let moveX = 0, moveZ = 0;
      if (scene.isKeyDown("w")) { moveX += flatDirX * speed; moveZ += flatDirZ * speed; }
      if (scene.isKeyDown("s")) { moveX -= flatDirX * speed; moveZ -= flatDirZ * speed; }
      if (scene.isKeyDown("a")) { moveX -= rightX * speed; moveZ -= rightZ * speed; }
      if (scene.isKeyDown("d")) { moveX += rightX * speed; moveZ += rightZ * speed; }

      // Normalize diagonal movement
      let moveLen = Math.sqrt(moveX * moveX + moveZ * moveZ);
      if (moveLen > speed && moveLen > 0) {
        moveX = moveX / moveLen * speed;
        moveZ = moveZ / moveLen * speed;
      }

      // Apply with collision
      tryMove(camX + moveX, camZ + moveZ);

      // World bounds
      if (camX < -10) camX = -10;
      if (camX > 10) camX = 10;
      if (camZ < -10) camZ = -10;
      if (camZ > 10) camZ = 10;

      // Jump
      if (scene.isKeyDown("space") && onGround) {
        velY = jumpForce;
        onGround = false;
      }

      // Gravity
      velY += gravity * dt;
      camY += velY * dt;

      // Ground collision
      if (camY <= groundY) {
        camY = groundY;
        velY = 0;
        onGround = true;
      }

      scene.setCamera({
        position: [camX, camY, camZ],
        target: [camX + dirX, camY + dirY, camZ + dirZ],
        fov: 60
      });

      scene.rotateMesh("cube1", 0, dt * 0.5, 0);
      scene.rotateMesh("cube2", dt * 0.3, 0, dt * 0.2);
    });

    scene.onDraw(function (ctx) {
      ctx.clear("#1a1a2e");

      let sprinting = scene.isKeyDown("Shift_L") || scene.isKeyDown("Shift_R");
      let status = sprinting ? "SPRINTING" : (onGround ? "walking" : "airborne");
      ctx.fillText("WASD: move | Mouse: look | Space: jump | Shift: sprint", 10, 20, "#aaaacc", 14);
      ctx.fillText(status, 10, 40, sprinting ? "#ffaa22" : "#666688", 12);
    });

    scene.start();
  }, []);

  return (
    <Box orientation="vertical" expand={true}>
      <Canvas id="cube" expand={true} />
    </Box>
  );
}

function App() {
  return <Game />;
}

$.onReady(function () {
  $.render("root", App);
});