import { Canvas } from "canvas";

function Game() {
  var [selected, setSelected] = useState(0);

  useEffect(function() {
    var canvas = new Canvas("cube", { width: 800, height: 600, framesPerSecond: 60 });

    // Rotation angles
    var rotX = 0.4;
    var rotY = 0.6;
    var rotZ = 0.0;

    // Mouse state
    var dragging = false;
    var lastMouseX = 0;
    var lastMouseY = 0;
    var mouseX = 0;
    var mouseY = 0;

    var autoRotate = true;
    var idleTimer = 0;

    var SIZE = 100;

    // Menu items
    var menuItems = [
      { label: "Cube", icon: "square" },
      { label: "Colors", icon: "palette" },
      { label: "Speed", icon: "fast" },
      { label: "Size", icon: "resize" },
      { label: "Reset", icon: "refresh" }
    ];
    var hoveredItem = -1;
    var menuAnimOffset = 0;

    // Color themes
    var themes = [
      ["#e74c3c", "#3498db", "#2ecc71", "#f39c12", "#9b59b6", "#1abc9c"],
      ["#ff6b6b", "#4ecdc4", "#45b7d1", "#96ceb4", "#ffeaa7", "#dfe6e9"],
      ["#fd79a8", "#6c5ce7", "#00cec9", "#fdcb6e", "#e17055", "#636e72"],
      ["#a29bfe", "#ff7675", "#74b9ff", "#55efc4", "#ffeaa7", "#fab1a0"]
    ];
    var currentTheme = 0;

    // Speed multiplier
    var speedMult = 1.0;
    var sizeTarget = 100;

    var vertices = [
      [-1, -1, -1], [ 1, -1, -1], [ 1,  1, -1], [-1,  1, -1],
      [-1, -1,  1], [ 1, -1,  1], [ 1,  1,  1], [-1,  1,  1]
    ];

    var faces = [
      { verts: [0, 1, 2, 3] },
      { verts: [5, 4, 7, 6] },
      { verts: [4, 0, 3, 7] },
      { verts: [1, 5, 6, 2] },
      { verts: [3, 2, 6, 7] },
      { verts: [4, 5, 1, 0] }
    ];

    var edges = [
      [0,1],[1,2],[2,3],[3,0],
      [4,5],[5,6],[6,7],[7,4],
      [0,4],[1,5],[2,6],[3,7]
    ];

    function rotatePoint(p, rx, ry, rz) {
      var cos, sin, x, y, z;
      // X rotation
      cos = Math.cos(rx); sin = Math.sin(rx);
      y = p[1] * cos - p[2] * sin;
      z = p[1] * sin + p[2] * cos;
      x = p[0];
      // Y rotation
      cos = Math.cos(ry); sin = Math.sin(ry);
      var x2 = x * cos + z * sin;
      var z2 = -x * sin + z * cos;
      // Z rotation
      cos = Math.cos(rz); sin = Math.sin(rz);
      var x3 = x2 * cos - y * sin;
      var y3 = x2 * sin + y * cos;
      return [x3, y3, z2];
    }

    function project(p, cx, cy) {
      var dist = 5;
      var scale = dist / (dist + p[2]);
      return [cx + p[0] * SIZE * scale, cy + p[1] * SIZE * scale, p[2], scale];
    }

    function transformVertices(cx, cy) {
      var tv = [];
      for (var i = 0; i < vertices.length; i++) {
        var p = rotatePoint(vertices[i], rotX, rotY, rotZ);
        tv.push(project(p, cx, cy));
      }
      return tv;
    }

    function faceDepth(face, tv) {
      var sum = 0;
      for (var i = 0; i < face.verts.length; i++) sum += tv[face.verts[i]][2];
      return sum / face.verts.length;
    }

    function faceNormalZ(face, tv) {
      var a = face.verts[0], b = face.verts[1], c = face.verts[2];
      var ux = tv[b][0] - tv[a][0], uy = tv[b][1] - tv[a][1];
      var vx = tv[c][0] - tv[a][0], vy = tv[c][1] - tv[a][1];
      return ux * vy - uy * vx;
    }

    function lerpColor(hex, factor) {
      var r = parseInt(hex.slice(1, 3), 16);
      var g = parseInt(hex.slice(3, 5), 16);
      var b = parseInt(hex.slice(5, 7), 16);
      if (factor > 1) {
        r = Math.min(255, Math.floor(r + (255 - r) * (factor - 1)));
        g = Math.min(255, Math.floor(g + (255 - g) * (factor - 1)));
        b = Math.min(255, Math.floor(b + (255 - b) * (factor - 1)));
      } else {
        r = Math.floor(r * factor);
        g = Math.floor(g * factor);
        b = Math.floor(b * factor);
      }
      var rh = r.toString(16); if (rh.length < 2) rh = "0" + rh;
      var gh = g.toString(16); if (gh.length < 2) gh = "0" + gh;
      var bh = b.toString(16); if (bh.length < 2) bh = "0" + bh;
      return "#" + rh + gh + bh;
    }

    function getMenuItemY(index) {
      return 120 + index * 64;
    }

    function hitTestMenu(mx, my) {
      for (var i = 0; i < menuItems.length; i++) {
        var iy = getMenuItemY(i);
        if (mx >= 20 && mx <= 220 && my >= iy && my <= iy + 48) {
          return i;
        }
      }
      return -1;
    }

    function handleMenuClick(index) {
      setSelected(index);
      if (index === 0) {
        // Cube — default, do nothing special
      } else if (index === 1) {
        // Colors — cycle theme
        currentTheme = (currentTheme + 1) % themes.length;
      } else if (index === 2) {
        // Speed — cycle speed
        if (speedMult < 1.5) speedMult = 2.0;
        else if (speedMult < 2.5) speedMult = 3.0;
        else if (speedMult < 3.5) speedMult = 4.0;
        else speedMult = 1.0;
      } else if (index === 3) {
        // Size — cycle size
        if (sizeTarget < 80) sizeTarget = 100;
        else if (sizeTarget < 120) sizeTarget = 140;
        else if (sizeTarget < 160) sizeTarget = 180;
        else sizeTarget = 60;
      } else if (index === 4) {
        // Reset
        rotX = 0.4; rotY = 0.6; rotZ = 0.0;
        currentTheme = 0;
        speedMult = 1.0;
        sizeTarget = 100;
        autoRotate = true;
        setSelected(0);
      }
    }

    // Draw a simple icon shape
    function drawIcon(context, type, x, y, color) {
      if (type === "square") {
        context.strokeRect(x, y, 16, 16, color, 2);
        context.fillRect(x + 4, y + 4, 8, 8, color);
      } else if (type === "palette") {
        context.fillCircle(x + 8, y + 8, 8, color);
        context.fillCircle(x + 4, y + 5, 2, "#0f0f1a");
        context.fillCircle(x + 10, y + 4, 2, "#0f0f1a");
        context.fillCircle(x + 13, y + 8, 2, "#0f0f1a");
        context.fillCircle(x + 6, y + 12, 2, "#0f0f1a");
      } else if (type === "fast") {
        context.fillTriangle(x, y, x, y + 16, x + 10, y + 8, color);
        context.fillTriangle(x + 8, y, x + 8, y + 16, x + 18, y + 8, color);
      } else if (type === "resize") {
        context.strokeRect(x + 2, y + 2, 12, 12, color, 2);
        context.fillRect(x + 10, y + 10, 6, 6, color);
      } else if (type === "refresh") {
        context.strokeCircle(x + 8, y + 8, 7, color, 2);
        context.fillTriangle(x + 12, y + 1, x + 16, y + 5, x + 10, y + 5, color);
      }
    }

    canvas.onUpdate(function(dt) {
      // Smooth size transition
      SIZE += (sizeTarget - SIZE) * 0.05;

      // Menu animation
      menuAnimOffset += dt;

      if (autoRotate) {
        rotY += 0.008 * speedMult;
        rotX += 0.004 * speedMult;
      } else {
        idleTimer += dt;
        if (idleTimer > 3) {
          autoRotate = true;
          idleTimer = 0;
        }
      }
    });

    canvas.onDraw(function(context) {
      var W = canvas.getWidth();
      var H = canvas.getHeight();
      var MENU_W = 240;
      var cubeAreaX = MENU_W;
      var cubeAreaW = W - MENU_W;
      var cubeCX = cubeAreaX + cubeAreaW / 2;
      var cubeCY = H / 2;

      var colors = themes[currentTheme];

      // Background
      context.clear("#0f0f1a");

      // Grid on cube area only
      for (var i = Math.floor(cubeAreaX / 40) * 40; i < W; i += 40) {
        context.drawLine(i, 0, i, H, "#151525", 1);
      }
      for (var i = 0; i < H; i += 40) {
        context.drawLine(cubeAreaX, i, W, i, "#151525", 1);
      }

      context.fillRect(0, 0, MENU_W, H, "#12121f");
      // Menu right border
      context.fillRect(MENU_W - 1, 0, 1, H, "#2a2a40");

      // Menu title area
      context.fillRect(0, 0, MENU_W, 80, "#16162a");
      context.fillRect(0, 78, MENU_W, 2, "#3a3a5a");

      // Title decoration — small cube icon
      var titleCubeX = 24;
      var titleCubeY = 25;
      context.fillRect(titleCubeX, titleCubeY, 24, 24, "#9b59b6");
      context.fillRect(titleCubeX + 2, titleCubeY + 2, 20, 20, "#a66bbe");
      context.fillRect(titleCubeX + 24, titleCubeY - 6, 12, 18, "#7d3c98");
      context.fillTriangle(
        titleCubeX, titleCubeY,
        titleCubeX + 24, titleCubeY,
        titleCubeX + 36, titleCubeY - 6,
        "#8e44ad"
      );

      // Title dots
      context.fillCircle(MENU_W - 30, 40, 3, "#4a4a6a");
      context.fillCircle(MENU_W - 42, 40, 3, "#4a4a6a");
      context.fillCircle(MENU_W - 54, 40, 3, "#4a4a6a");

      // Title text
      context.fillText("Cube Demo", 70, 28, "#c0c0e0", 20);

      // Menu items
      for (var i = 0; i < menuItems.length; i++) {
        var iy = getMenuItemY(i);
        var isHovered = (hoveredItem === i);
        var isSelected = (selected === i);

        // Item background
        if (isSelected) {
          context.fillRect(0, iy, MENU_W - 1, 48, "#1e1e38");
          // Accent bar on the left
          context.fillRect(0, iy, 4, 48, colors[i % colors.length]);
        } else if (isHovered) {
          context.fillRect(0, iy, MENU_W - 1, 48, "#181830");
        }

        // Icon
        var iconColor = isSelected ? colors[i % colors.length] : "#5a5a7a";
        drawIcon(context, menuItems[i].icon, 24, iy + 16, iconColor);

        // Label
        var labelColor = isSelected ? "#e0e0f0" : (isHovered ? "#8888aa" : "#5a5a7a");
        context.fillText(menuItems[i].label, 52, iy + 14, labelColor, 12);

        // Separator
        if (i < menuItems.length - 1) {
          context.fillRect(20, iy + 48, MENU_W - 40, 1, "#1a1a30");
        }
      }

      // Bottom status area
      context.fillRect(0, H - 56, MENU_W, 56, "#16162a");
      context.fillRect(0, H - 56, MENU_W, 1, "#2a2a40");

      // Row 1: Speed and Theme side by side
      context.fillText("Speed", 16, H - 52, "#5a5a7a", 9);
      var speedDots = 0;
      if (speedMult >= 2.0) speedDots = 1;
      if (speedMult >= 3.0) speedDots = 2;
      if (speedMult >= 4.0) speedDots = 3;
      for (var i = 0; i < 3; i++) {
        var dotColor = (i < speedDots) ? "#2ecc71" : "#2a2a40";
        context.fillCircle(66 + i * 12, H - 47, 4, dotColor);
      }

      context.fillText("Theme", 120, H - 52, "#5a5a7a", 9);
      for (var i = 0; i < 6; i++) {
        context.fillRect(168 + i * 12, H - 52, 9, 9, colors[i]);
      }

      // Row 2: Size with bar
      context.fillText("Size", 16, H - 30, "#5a5a7a", 9);
      var sizePercent = (sizeTarget - 60) / 120;
      context.fillRect(54, H - 26, 80, 3, "#2a2a40");
      context.fillRect(54, H - 26, 80 * sizePercent, 4, "#3498db");

      var tv = transformVertices(cubeCX, cubeCY);

      var sortedFaces = [];
      for (var i = 0; i < faces.length; i++) {
        sortedFaces.push({ index: i, depth: faceDepth(faces[i], tv) });
      }
      sortedFaces.sort(function(a, b) { return b.depth - a.depth; });

      for (var fi = 0; fi < sortedFaces.length; fi++) {
        var faceIdx = sortedFaces[fi].index;
        var face = faces[faceIdx];
        var nz = faceNormalZ(face, tv);
        if (nz < 0) continue;

        var v = face.verts;
        var faceColor = colors[faceIdx % colors.length];

        var lightFactor = 0.5 + (nz / (cubeAreaW * 0.5)) * 0.8;
        if (lightFactor < 0.3) lightFactor = 0.3;
        if (lightFactor > 1.3) lightFactor = 1.3;
        var shaded = lerpColor(faceColor, lightFactor);

        context.fillTriangle(
          tv[v[0]][0], tv[v[0]][1], tv[v[1]][0], tv[v[1]][1],
          tv[v[2]][0], tv[v[2]][1], shaded
        );
        context.fillTriangle(
          tv[v[0]][0], tv[v[0]][1], tv[v[2]][0], tv[v[2]][1],
          tv[v[3]][0], tv[v[3]][1], shaded
        );

        var highlight = lerpColor(faceColor, 1.4);
        for (var ei = 0; ei < 4; ei++) {
          var a = v[ei], b = v[(ei + 1) % 4];
          context.drawLine(tv[a][0], tv[a][1], tv[b][0], tv[b][1], highlight, 2);
        }
      }

      // Edges
      for (var i = 0; i < edges.length; i++) {
        var a = edges[i][0], b = edges[i][1];
        context.drawLine(tv[a][0], tv[a][1], tv[b][0], tv[b][1], "#ffffff15", 1);
      }

      // Vertices
      for (var i = 0; i < tv.length; i++) {
        var s = tv[i][3];
        context.fillCircle(tv[i][0], tv[i][1], 3 * s, "#ffffff60");
      }

      // Hint
      context.fillText("Drag to rotate", cubeCX - 50, H - 30, "#3a3a5a", 12);
    });

    canvas.onMouseDown(function(x, y) {
      var hit = hitTestMenu(x, y);
      if (hit >= 0) {
        handleMenuClick(hit);
        return;
      }
      // Dragging cube
      dragging = true;
      lastMouseX = x;
      lastMouseY = y;
      autoRotate = false;
      idleTimer = 0;
    });

    canvas.onMouseUp(function(x, y) {
      dragging = false;
    });

    canvas.onMouseMove(function(x, y) {
      mouseX = x;
      mouseY = y;
      hoveredItem = hitTestMenu(x, y);

      if (!dragging) return;
      var dx = x - lastMouseX;
      var dy = y - lastMouseY;
      rotY -= dx * 0.01;
      rotX -= dy * 0.01;
      lastMouseX = x;
      lastMouseY = y;
      idleTimer = 0;
    });

    canvas.start();
  }, []);

  return (
    <Box orientation="vertical" expand="true">
      <Canvas id="cube" expand="true" />
    </Box>
  );
}

function App() {
  return <Game />;
}

$.onReady(function() {
  $.render("root", App);
});