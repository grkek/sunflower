import { Canvas } from "canvas";
import Stigma, { useState, useEffect } from "stigma";

function Game() {
  let [score, setScore] = useState(0);
  let [level, setLevel] = useState(1);
  let [gameState, setGameState] = useState("playing"); // "playing", "dead", "won"

  let player = {
    x: 60, y: 400,
    vx: 0, vy: 0,
    w: 24, h: 32,
    speed: 5, jumpForce: -12,
    grounded: false, facing: 1,
    // Animation
    frame: 0, frameTimer: 0
  };

  let camera = { x: 0, y: 0 };
  let graceFrames = 30; // Don't kill the player for the first 30 frames

  let GRAVITY = 0.45;
  let FRICTION = 0.82;
  let MAX_FALL = 12;

  // Level data — platforms, coins, and goal
  let platforms = [];
  let coins = [];
  let goal = { x: 0, y: 0, w: 32, h: 48 };
  let particles = [];

  function buildLevel(level) {
    platforms = [];
    coins = [];
    particles = [];
    graceFrames = 30;

    if (level === 1) {
      // Full ground, easy platforms, introduction to jumping
      platforms.push({ x: 0, y: 500, w: 600, h: 40, color: "#4a6741" });
      platforms.push({ x: 700, y: 500, w: 800, h: 40, color: "#4a6741" });
      platforms.push({ x: 1600, y: 500, w: 600, h: 40, color: "#4a6741" });

      platforms.push({ x: 200, y: 400, w: 120, h: 16, color: "#8b6914" });
      platforms.push({ x: 420, y: 350, w: 120, h: 16, color: "#8b6914" });
      platforms.push({ x: 650, y: 380, w: 140, h: 16, color: "#8b6914" });
      platforms.push({ x: 900, y: 350, w: 120, h: 16, color: "#8b6914" });
      platforms.push({ x: 1150, y: 380, w: 140, h: 16, color: "#8b6914" });
      platforms.push({ x: 1400, y: 350, w: 120, h: 16, color: "#8b6914" });

      coins.push({ x: 240, y: 360, collected: false });
      coins.push({ x: 460, y: 310, collected: false });
      coins.push({ x: 700, y: 340, collected: false });
      coins.push({ x: 940, y: 310, collected: false });
      coins.push({ x: 1200, y: 340, collected: false });
      coins.push({ x: 1440, y: 310, collected: false });

      goal.x = 1900; goal.y = 452;

    } else if (level === 2) {
      platforms.push({ x: 0, y: 500, w: 400, h: 40, color: "#4a6741" });
      platforms.push({ x: 550, y: 500, w: 350, h: 40, color: "#4a6741" });
      platforms.push({ x: 1050, y: 500, w: 400, h: 40, color: "#4a6741" });
      platforms.push({ x: 1600, y: 500, w: 500, h: 40, color: "#4a6741" });

      platforms.push({ x: 200, y: 380, w: 120, h: 16, color: "#8b6914" });
      platforms.push({ x: 450, y: 300, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 700, y: 360, w: 140, h: 16, color: "#8b6914" });
      platforms.push({ x: 950, y: 280, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 1200, y: 340, w: 120, h: 16, color: "#8b6914" });
      platforms.push({ x: 1450, y: 380, w: 140, h: 16, color: "#8b6914" });
      platforms.push({ x: 1700, y: 300, w: 120, h: 16, color: "#8b6914" });

      platforms.push({ x: 350, y: 180, w: 80, h: 16, color: "#6b4914" });
      platforms.push({ x: 900, y: 160, w: 80, h: 16, color: "#6b4914" });

      coins.push({ x: 240, y: 340, collected: false });
      coins.push({ x: 470, y: 260, collected: false });
      coins.push({ x: 740, y: 320, collected: false });
      coins.push({ x: 370, y: 140, collected: false });
      coins.push({ x: 920, y: 120, collected: false });
      coins.push({ x: 980, y: 240, collected: false });
      coins.push({ x: 1250, y: 300, collected: false });
      coins.push({ x: 1500, y: 340, collected: false });
      coins.push({ x: 1740, y: 260, collected: false });

      goal.x = 1950; goal.y = 452;

    } else if (level === 3) {
      // Ascending platforms, no ground in the middle
      platforms.push({ x: 0, y: 500, w: 250, h: 40, color: "#41574a" });
      platforms.push({ x: 300, y: 450, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 480, y: 400, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 650, y: 350, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 820, y: 300, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 1000, y: 250, w: 120, h: 16, color: "#8b6914" });
      // Descending
      platforms.push({ x: 1200, y: 300, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 1380, y: 350, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 1550, y: 400, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 1720, y: 450, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 1880, y: 500, w: 300, h: 40, color: "#41574a" });

      // Bonus high path
      platforms.push({ x: 700, y: 180, w: 80, h: 16, color: "#6b4914" });
      platforms.push({ x: 900, y: 130, w: 80, h: 16, color: "#6b4914" });
      platforms.push({ x: 1100, y: 160, w: 80, h: 16, color: "#6b4914" });

      coins.push({ x: 330, y: 410, collected: false });
      coins.push({ x: 510, y: 360, collected: false });
      coins.push({ x: 680, y: 310, collected: false });
      coins.push({ x: 850, y: 260, collected: false });
      coins.push({ x: 1040, y: 210, collected: false });
      coins.push({ x: 730, y: 140, collected: false });
      coins.push({ x: 930, y: 90, collected: false });
      coins.push({ x: 1130, y: 120, collected: false });
      coins.push({ x: 1230, y: 260, collected: false });
      coins.push({ x: 1580, y: 360, collected: false });

      goal.x = 2050; goal.y = 452;

    } else if (level === 4) {
      // Many gaps in the ground, need precise jumping
      platforms.push({ x: 0, y: 500, w: 150, h: 40, color: "#3d5c41" });
      platforms.push({ x: 250, y: 500, w: 120, h: 40, color: "#3d5c41" });
      platforms.push({ x: 480, y: 500, w: 100, h: 40, color: "#3d5c41" });
      platforms.push({ x: 700, y: 500, w: 80, h: 40, color: "#3d5c41" });
      platforms.push({ x: 900, y: 500, w: 120, h: 40, color: "#3d5c41" });
      platforms.push({ x: 1150, y: 500, w: 100, h: 40, color: "#3d5c41" });
      platforms.push({ x: 1380, y: 500, w: 80, h: 40, color: "#3d5c41" });
      platforms.push({ x: 1580, y: 500, w: 120, h: 40, color: "#3d5c41" });
      platforms.push({ x: 1830, y: 500, w: 300, h: 40, color: "#3d5c41" });

      // Mid-air helpers
      platforms.push({ x: 180, y: 430, w: 50, h: 16, color: "#8b6914" });
      platforms.push({ x: 400, y: 420, w: 50, h: 16, color: "#8b6914" });
      platforms.push({ x: 610, y: 410, w: 60, h: 16, color: "#8b6914" });
      platforms.push({ x: 810, y: 400, w: 60, h: 16, color: "#8b6914" });
      platforms.push({ x: 1060, y: 390, w: 60, h: 16, color: "#8b6914" });
      platforms.push({ x: 1280, y: 380, w: 60, h: 16, color: "#8b6914" });
      platforms.push({ x: 1490, y: 400, w: 60, h: 16, color: "#8b6914" });
      platforms.push({ x: 1720, y: 420, w: 60, h: 16, color: "#8b6914" });

      // Upper route
      platforms.push({ x: 300, y: 280, w: 80, h: 16, color: "#6b4914" });
      platforms.push({ x: 550, y: 240, w: 80, h: 16, color: "#6b4914" });
      platforms.push({ x: 800, y: 200, w: 80, h: 16, color: "#6b4914" });
      platforms.push({ x: 1050, y: 220, w: 80, h: 16, color: "#6b4914" });
      platforms.push({ x: 1300, y: 180, w: 80, h: 16, color: "#6b4914" });
      platforms.push({ x: 1550, y: 240, w: 80, h: 16, color: "#6b4914" });

      coins.push({ x: 200, y: 390, collected: false });
      coins.push({ x: 420, y: 380, collected: false });
      coins.push({ x: 630, y: 370, collected: false });
      coins.push({ x: 830, y: 360, collected: false });
      coins.push({ x: 330, y: 240, collected: false });
      coins.push({ x: 580, y: 200, collected: false });
      coins.push({ x: 830, y: 160, collected: false });
      coins.push({ x: 1080, y: 180, collected: false });
      coins.push({ x: 1330, y: 140, collected: false });
      coins.push({ x: 1580, y: 200, collected: false });
      coins.push({ x: 1500, y: 360, collected: false });
      coins.push({ x: 1740, y: 380, collected: false });

      goal.x = 2000; goal.y = 452;

    } else if (level === 5) {
      // Vertical level — climb up then traverse right
      platforms.push({ x: 0, y: 500, w: 200, h: 40, color: "#3d4157" });
      platforms.push({ x: 50, y: 420, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 180, y: 340, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 50, y: 260, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 180, y: 180, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 50, y: 100, w: 120, h: 16, color: "#8b6914" });

      // Top traverse
      platforms.push({ x: 250, y: 100, w: 100, h: 16, color: "#6b4914" });
      platforms.push({ x: 430, y: 120, w: 80, h: 16, color: "#6b4914" });
      platforms.push({ x: 590, y: 100, w: 80, h: 16, color: "#6b4914" });
      platforms.push({ x: 750, y: 130, w: 80, h: 16, color: "#6b4914" });
      platforms.push({ x: 920, y: 100, w: 80, h: 16, color: "#6b4914" });
      platforms.push({ x: 1080, y: 120, w: 80, h: 16, color: "#6b4914" });

      // Descent on the right
      platforms.push({ x: 1230, y: 180, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 1400, y: 260, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 1560, y: 340, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 1720, y: 420, w: 100, h: 16, color: "#8b6914" });
      platforms.push({ x: 1880, y: 500, w: 200, h: 40, color: "#3d4157" });

      coins.push({ x: 80, y: 380, collected: false });
      coins.push({ x: 210, y: 300, collected: false });
      coins.push({ x: 80, y: 220, collected: false });
      coins.push({ x: 210, y: 140, collected: false });
      coins.push({ x: 280, y: 60, collected: false });
      coins.push({ x: 460, y: 80, collected: false });
      coins.push({ x: 620, y: 60, collected: false });
      coins.push({ x: 780, y: 90, collected: false });
      coins.push({ x: 950, y: 60, collected: false });
      coins.push({ x: 1110, y: 80, collected: false });
      coins.push({ x: 1260, y: 140, collected: false });
      coins.push({ x: 1430, y: 220, collected: false });

      goal.x = 1950; goal.y = 452;

    } else if (level === 6) {
      // No ground at all — everything is platforms
      platforms.push({ x: 20, y: 460, w: 100, h: 20, color: "#4a5741" });
      platforms.push({ x: 200, y: 400, w: 80, h: 16, color: "#8b6914" });
      platforms.push({ x: 360, y: 350, w: 80, h: 16, color: "#8b6914" });
      platforms.push({ x: 500, y: 420, w: 80, h: 16, color: "#8b6914" });
      platforms.push({ x: 660, y: 350, w: 80, h: 16, color: "#8b6914" });
      platforms.push({ x: 820, y: 280, w: 80, h: 16, color: "#8b6914" });
      platforms.push({ x: 960, y: 380, w: 80, h: 16, color: "#8b6914" });
      platforms.push({ x: 1100, y: 300, w: 80, h: 16, color: "#8b6914" });
      platforms.push({ x: 1250, y: 220, w: 80, h: 16, color: "#8b6914" });
      platforms.push({ x: 1400, y: 340, w: 80, h: 16, color: "#8b6914" });
      platforms.push({ x: 1550, y: 260, w: 80, h: 16, color: "#8b6914" });
      platforms.push({ x: 1700, y: 380, w: 80, h: 16, color: "#8b6914" });
      platforms.push({ x: 1850, y: 300, w: 80, h: 16, color: "#8b6914" });
      platforms.push({ x: 2000, y: 420, w: 100, h: 20, color: "#4a5741" });

      // Secret high path
      platforms.push({ x: 450, y: 180, w: 60, h: 16, color: "#6b4914" });
      platforms.push({ x: 650, y: 140, w: 60, h: 16, color: "#6b4914" });
      platforms.push({ x: 850, y: 110, w: 60, h: 16, color: "#6b4914" });
      platforms.push({ x: 1050, y: 130, w: 60, h: 16, color: "#6b4914" });
      platforms.push({ x: 1250, y: 100, w: 60, h: 16, color: "#6b4914" });

      coins.push({ x: 230, y: 360, collected: false });
      coins.push({ x: 390, y: 310, collected: false });
      coins.push({ x: 530, y: 380, collected: false });
      coins.push({ x: 690, y: 310, collected: false });
      coins.push({ x: 850, y: 240, collected: false });
      coins.push({ x: 480, y: 140, collected: false });
      coins.push({ x: 680, y: 100, collected: false });
      coins.push({ x: 880, y: 70, collected: false });
      coins.push({ x: 1080, y: 90, collected: false });
      coins.push({ x: 1280, y: 60, collected: false });
      coins.push({ x: 1430, y: 300, collected: false });
      coins.push({ x: 1580, y: 220, collected: false });
      coins.push({ x: 1730, y: 340, collected: false });
      coins.push({ x: 1880, y: 260, collected: false });

      goal.x = 2020; goal.y = 372;

    } else if (level === 7) {
      // Narrow platforms alternating left-right, long drops between
      platforms.push({ x: 0, y: 500, w: 180, h: 40, color: "#3d4a57" });

      platforms.push({ x: 280, y: 440, w: 70, h: 16, color: "#8b6914" });
      platforms.push({ x: 120, y: 370, w: 70, h: 16, color: "#8b6914" });
      platforms.push({ x: 300, y: 300, w: 70, h: 16, color: "#8b6914" });
      platforms.push({ x: 140, y: 230, w: 70, h: 16, color: "#8b6914" });
      platforms.push({ x: 320, y: 160, w: 70, h: 16, color: "#8b6914" });

      // Bridge at top
      platforms.push({ x: 450, y: 140, w: 120, h: 16, color: "#6b4914" });
      platforms.push({ x: 630, y: 160, w: 100, h: 16, color: "#6b4914" });
      platforms.push({ x: 800, y: 140, w: 100, h: 16, color: "#6b4914" });
      platforms.push({ x: 970, y: 120, w: 100, h: 16, color: "#6b4914" });

      // Descent zigzag
      platforms.push({ x: 1140, y: 180, w: 70, h: 16, color: "#8b6914" });
      platforms.push({ x: 1300, y: 250, w: 70, h: 16, color: "#8b6914" });
      platforms.push({ x: 1140, y: 320, w: 70, h: 16, color: "#8b6914" });
      platforms.push({ x: 1300, y: 390, w: 70, h: 16, color: "#8b6914" });
      platforms.push({ x: 1450, y: 450, w: 70, h: 16, color: "#8b6914" });
      platforms.push({ x: 1600, y: 500, w: 200, h: 40, color: "#3d4a57" });

      coins.push({ x: 300, y: 400, collected: false });
      coins.push({ x: 140, y: 330, collected: false });
      coins.push({ x: 320, y: 260, collected: false });
      coins.push({ x: 160, y: 190, collected: false });
      coins.push({ x: 340, y: 120, collected: false });
      coins.push({ x: 490, y: 100, collected: false });
      coins.push({ x: 660, y: 120, collected: false });
      coins.push({ x: 830, y: 100, collected: false });
      coins.push({ x: 1000, y: 80, collected: false });
      coins.push({ x: 1160, y: 140, collected: false });
      coins.push({ x: 1320, y: 210, collected: false });
      coins.push({ x: 1160, y: 280, collected: false });
      coins.push({ x: 1320, y: 350, collected: false });
      coins.push({ x: 1470, y: 410, collected: false });

      goal.x = 1700; goal.y = 452;

    } else if (level === 8) {
      // Very small platforms with long gaps — precision jumping
      platforms.push({ x: 0, y: 500, w: 120, h: 40, color: "#574141" });

      platforms.push({ x: 200, y: 460, w: 45, h: 14, color: "#8b6914" });
      platforms.push({ x: 340, y: 420, w: 45, h: 14, color: "#8b6914" });
      platforms.push({ x: 490, y: 380, w: 45, h: 14, color: "#8b6914" });
      platforms.push({ x: 640, y: 340, w: 45, h: 14, color: "#8b6914" });
      platforms.push({ x: 790, y: 300, w: 45, h: 14, color: "#8b6914" });
      platforms.push({ x: 940, y: 340, w: 45, h: 14, color: "#8b6914" });
      platforms.push({ x: 1090, y: 380, w: 45, h: 14, color: "#8b6914" });
      platforms.push({ x: 1240, y: 340, w: 45, h: 14, color: "#8b6914" });
      platforms.push({ x: 1390, y: 300, w: 45, h: 14, color: "#8b6914" });
      platforms.push({ x: 1540, y: 260, w: 45, h: 14, color: "#8b6914" });
      platforms.push({ x: 1690, y: 300, w: 45, h: 14, color: "#8b6914" });
      platforms.push({ x: 1840, y: 360, w: 45, h: 14, color: "#8b6914" });
      platforms.push({ x: 1990, y: 420, w: 45, h: 14, color: "#8b6914" });
      platforms.push({ x: 2100, y: 500, w: 120, h: 40, color: "#574141" });

      // High reward platforms
      platforms.push({ x: 550, y: 180, w: 50, h: 14, color: "#6b4914" });
      platforms.push({ x: 800, y: 140, w: 50, h: 14, color: "#6b4914" });
      platforms.push({ x: 1050, y: 160, w: 50, h: 14, color: "#6b4914" });
      platforms.push({ x: 1400, y: 140, w: 50, h: 14, color: "#6b4914" });

      coins.push({ x: 215, y: 420, collected: false });
      coins.push({ x: 355, y: 380, collected: false });
      coins.push({ x: 505, y: 340, collected: false });
      coins.push({ x: 655, y: 300, collected: false });
      coins.push({ x: 805, y: 260, collected: false });
      coins.push({ x: 565, y: 140, collected: false });
      coins.push({ x: 815, y: 100, collected: false });
      coins.push({ x: 1065, y: 120, collected: false });
      coins.push({ x: 1415, y: 100, collected: false });
      coins.push({ x: 1555, y: 220, collected: false });
      coins.push({ x: 1705, y: 260, collected: false });
      coins.push({ x: 1855, y: 320, collected: false });
      coins.push({ x: 2005, y: 380, collected: false });

      goal.x = 2130; goal.y = 452;

    } else if (level === 9) {
      // Long level, mixed challenges, very few safe spots
      platforms.push({ x: 0, y: 500, w: 100, h: 40, color: "#57413d" });

      // Section 1: Quick hops
      platforms.push({ x: 160, y: 470, w: 50, h: 14, color: "#8b6914" });
      platforms.push({ x: 280, y: 440, w: 50, h: 14, color: "#8b6914" });
      platforms.push({ x: 400, y: 470, w: 50, h: 14, color: "#8b6914" });
      platforms.push({ x: 520, y: 440, w: 50, h: 14, color: "#8b6914" });

      // Section 2: Climb
      platforms.push({ x: 640, y: 400, w: 60, h: 14, color: "#8b6914" });
      platforms.push({ x: 760, y: 340, w: 60, h: 14, color: "#8b6914" });
      platforms.push({ x: 880, y: 280, w: 60, h: 14, color: "#8b6914" });
      platforms.push({ x: 1000, y: 220, w: 60, h: 14, color: "#8b6914" });

      // Section 3: High traverse
      platforms.push({ x: 1150, y: 200, w: 50, h: 14, color: "#6b4914" });
      platforms.push({ x: 1280, y: 180, w: 50, h: 14, color: "#6b4914" });
      platforms.push({ x: 1410, y: 160, w: 50, h: 14, color: "#6b4914" });
      platforms.push({ x: 1540, y: 140, w: 50, h: 14, color: "#6b4914" });
      platforms.push({ x: 1670, y: 160, w: 50, h: 14, color: "#6b4914" });

      // Section 4: Drop down carefully
      platforms.push({ x: 1800, y: 220, w: 50, h: 14, color: "#8b6914" });
      platforms.push({ x: 1920, y: 300, w: 50, h: 14, color: "#8b6914" });
      platforms.push({ x: 2040, y: 380, w: 50, h: 14, color: "#8b6914" });
      platforms.push({ x: 2160, y: 460, w: 50, h: 14, color: "#8b6914" });
      platforms.push({ x: 2280, y: 500, w: 120, h: 40, color: "#57413d" });

      coins.push({ x: 180, y: 430, collected: false });
      coins.push({ x: 300, y: 400, collected: false });
      coins.push({ x: 420, y: 430, collected: false });
      coins.push({ x: 540, y: 400, collected: false });
      coins.push({ x: 660, y: 360, collected: false });
      coins.push({ x: 780, y: 300, collected: false });
      coins.push({ x: 900, y: 240, collected: false });
      coins.push({ x: 1020, y: 180, collected: false });
      coins.push({ x: 1170, y: 160, collected: false });
      coins.push({ x: 1300, y: 140, collected: false });
      coins.push({ x: 1430, y: 120, collected: false });
      coins.push({ x: 1560, y: 100, collected: false });
      coins.push({ x: 1690, y: 120, collected: false });
      coins.push({ x: 1820, y: 180, collected: false });
      coins.push({ x: 1940, y: 260, collected: false });
      coins.push({ x: 2060, y: 340, collected: false });
      coins.push({ x: 2180, y: 420, collected: false });

      goal.x = 2320; goal.y = 452;

    } else if (level === 10) {
      // Brutal — tiny platforms, huge gaps, vertical and horizontal challenges
      platforms.push({ x: 0, y: 500, w: 80, h: 40, color: "#571d1d" });

      // Ascending tiny platforms
      platforms.push({ x: 140, y: 460, w: 40, h: 12, color: "#8b5514" });
      platforms.push({ x: 260, y: 410, w: 40, h: 12, color: "#8b5514" });
      platforms.push({ x: 380, y: 360, w: 40, h: 12, color: "#8b5514" });
      platforms.push({ x: 260, y: 300, w: 40, h: 12, color: "#8b5514" });
      platforms.push({ x: 140, y: 240, w: 40, h: 12, color: "#8b5514" });
      platforms.push({ x: 260, y: 180, w: 40, h: 12, color: "#8b5514" });
      platforms.push({ x: 400, y: 130, w: 40, h: 12, color: "#8b5514" });

      // Sky bridge — very narrow
      platforms.push({ x: 520, y: 110, w: 35, h: 12, color: "#6b3514" });
      platforms.push({ x: 640, y: 100, w: 35, h: 12, color: "#6b3514" });
      platforms.push({ x: 760, y: 90, w: 35, h: 12, color: "#6b3514" });
      platforms.push({ x: 880, y: 100, w: 35, h: 12, color: "#6b3514" });
      platforms.push({ x: 1000, y: 110, w: 35, h: 12, color: "#6b3514" });

      // Freefall section — platforms scattered in a void
      platforms.push({ x: 1120, y: 170, w: 40, h: 12, color: "#8b5514" });
      platforms.push({ x: 1260, y: 240, w: 40, h: 12, color: "#8b5514" });
      platforms.push({ x: 1140, y: 310, w: 40, h: 12, color: "#8b5514" });
      platforms.push({ x: 1280, y: 380, w: 40, h: 12, color: "#8b5514" });
      platforms.push({ x: 1420, y: 320, w: 40, h: 12, color: "#8b5514" });
      platforms.push({ x: 1560, y: 260, w: 40, h: 12, color: "#8b5514" });
      platforms.push({ x: 1700, y: 200, w: 40, h: 12, color: "#8b5514" });

      // Final approach
      platforms.push({ x: 1840, y: 260, w: 40, h: 12, color: "#8b5514" });
      platforms.push({ x: 1960, y: 340, w: 40, h: 12, color: "#8b5514" });
      platforms.push({ x: 2080, y: 420, w: 40, h: 12, color: "#8b5514" });
      platforms.push({ x: 2200, y: 500, w: 100, h: 40, color: "#571d1d" });

      coins.push({ x: 150, y: 420, collected: false });
      coins.push({ x: 270, y: 370, collected: false });
      coins.push({ x: 390, y: 320, collected: false });
      coins.push({ x: 270, y: 260, collected: false });
      coins.push({ x: 150, y: 200, collected: false });
      coins.push({ x: 270, y: 140, collected: false });
      coins.push({ x: 410, y: 90, collected: false });
      coins.push({ x: 530, y: 70, collected: false });
      coins.push({ x: 650, y: 60, collected: false });
      coins.push({ x: 770, y: 50, collected: false });
      coins.push({ x: 890, y: 60, collected: false });
      coins.push({ x: 1010, y: 70, collected: false });
      coins.push({ x: 1130, y: 130, collected: false });
      coins.push({ x: 1270, y: 200, collected: false });
      coins.push({ x: 1150, y: 270, collected: false });
      coins.push({ x: 1290, y: 340, collected: false });
      coins.push({ x: 1430, y: 280, collected: false });
      coins.push({ x: 1570, y: 220, collected: false });
      coins.push({ x: 1710, y: 160, collected: false });
      coins.push({ x: 1850, y: 220, collected: false });
      coins.push({ x: 1970, y: 300, collected: false });
      coins.push({ x: 2090, y: 380, collected: false });

      goal.x = 2240; goal.y = 452;

    } else {
      // All 10 levels complete — victory!
      setGameState("won");
      return;
    }

    // Reset player
    player.x = 60;
    player.y = 400;
    player.vx = 0;
    player.vy = 0;
    player.grounded = false;
  }

  function spawnParticles(x, y, color, count) {
    for (var i = 0; i < count; i++) {
      particles.push({
        x: x, y: y,
        vx: (Math.random() - 0.5) * 6,
        vy: (Math.random() - 1) * 4,
        life: 1.0,
        color: color,
        size: 2 + Math.random() * 3
      });
    }
  }

  function resetPlayer() {
    player.x = 60;
    player.y = 400;
    player.vx = 0;
    player.vy = 0;
  }

  useEffect(function() {
    var canvas = new Canvas("game", { width: 900, height: 600, framesPerSecond: 60 });

    buildLevel(1);

    canvas.onUpdate(function(dt) {
      if (gameState !== "playing") return;

      var W = canvas.getWidth();
      var H = canvas.getHeight();

      // Input
      var moveLeft = canvas.isKeyDown("A") || canvas.isKeyDown("Left");
      var moveRight = canvas.isKeyDown("D") || canvas.isKeyDown("Right");
      var jump = canvas.isKeyDown("W") || canvas.isKeyDown("Up") || canvas.isKeyDown("Space");

      // Horizontal movement
      if (moveLeft) {
        player.vx -= player.speed * 0.4;
        player.facing = -1;
      }
      if (moveRight) {
        player.vx += player.speed * 0.4;
        player.facing = 1;
      }
      player.vx *= FRICTION;

      // Clamp horizontal speed
      if (player.vx > player.speed) player.vx = player.speed;
      if (player.vx < -player.speed) player.vx = -player.speed;
      if (Math.abs(player.vx) < 0.1) player.vx = 0;

      // Jump
      if (jump && player.grounded) {
        player.vy = player.jumpForce;
        player.grounded = false;
        spawnParticles(player.x + player.w / 2, player.y + player.h, "#aaaaaa", 5);
      }

      // Gravity
      player.vy += GRAVITY;
      if (player.vy > MAX_FALL) player.vy = MAX_FALL;

      // Move X
      player.x += player.vx;

      // Collide X
      for (var i = 0; i < platforms.length; i++) {
        var p = platforms[i];
        if (player.x + player.w > p.x && player.x < p.x + p.w &&
            player.y + player.h > p.y && player.y < p.y + p.h) {
          if (player.vx > 0) {
            player.x = p.x - player.w;
          } else if (player.vx < 0) {
            player.x = p.x + p.w;
          }
          player.vx = 0;
        }
      }

      // Move Y
      player.y += player.vy;
      player.grounded = false;

      // Collide Y
      for (var i = 0; i < platforms.length; i++) {
        var p = platforms[i];
        if (player.x + player.w > p.x && player.x < p.x + p.w &&
            player.y + player.h > p.y && player.y < p.y + p.h) {
          if (player.vy > 0) {
            player.y = p.y - player.h;
            player.grounded = true;
          } else if (player.vy < 0) {
            player.y = p.y + p.h;
          }
          player.vy = 0;
        }
      }

      // Fall off screen — restart the level
      if (graceFrames > 0) {
        graceFrames--;
      } else if (player.y > H + 100) {
        spawnParticles(player.x + player.w / 2, player.y, "#ff4444", 10);
        score = 0; setScore(0);
        level = 1; setLevel(1);
        buildLevel(1);
      }

      // Collect coins
      for (var i = 0; i < coins.length; i++) {
        var c = coins[i];
        if (c.collected) continue;
        var cx = c.x + 8;
        var cy = c.y + 8;
        var px = player.x + player.w / 2;
        var py = player.y + player.h / 2;
        var dist = Math.sqrt((cx - px) * (cx - px) + (cy - py) * (cy - py));
        if (dist < 20) {
          c.collected = true;
          score++;
          setScore(score);
          spawnParticles(c.x + 8, c.y + 8, "#ffdd00", 8);
        }
      }

      // Reach goal
      if (player.x + player.w > goal.x && player.x < goal.x + goal.w &&
          player.y + player.h > goal.y && player.y < goal.y + goal.h) {
        level++;
        setLevel(level);
        spawnParticles(goal.x + goal.w / 2, goal.y + goal.h / 2, "#44ff44", 20);
        buildLevel(level);
      }

      // Animation
      if (Math.abs(player.vx) > 0.5 && player.grounded) {
        player.frameTimer += 1;
        if (player.frameTimer > 6) {
          player.frame = (player.frame + 1) % 4;
          player.frameTimer = 0;
        }
      } else {
        player.frame = 0;
        player.frameTimer = 0;
      }

      // Update particles
      for (var i = particles.length - 1; i >= 0; i--) {
        var pt = particles[i];
        pt.x += pt.vx;
        pt.y += pt.vy;
        pt.vy += 0.15;
        pt.life -= 0.025;
        if (pt.life <= 0) {
          particles.splice(i, 1);
        }
      }

      // Camera follows player
      camera.x = player.x - W / 3;
      camera.y = player.y - H / 2;
      if (camera.x < 0) camera.x = 0;
      if (camera.y < 0) camera.y = 0;
    });

    canvas.onDraw(function(context) {
      var W = canvas.getWidth();
      var H = canvas.getHeight();

      // Sky gradient (drawn as horizontal bands)
      context.clear("#1a1a2e");
      context.fillRect(0, 0, W, H * 0.3, "#16213e");
      context.fillRect(0, H * 0.3, W, H * 0.3, "#1a1a2e");
      context.fillRect(0, H * 0.6, W, H * 0.4, "#0f3460");

      // Stars (static, not affected by camera)
      for (var i = 0; i < 30; i++) {
        var sx = (i * 137 + 50) % W;
        var sy = (i * 97 + 20) % (H * 0.5);
        var brightness = 0.3 + (i % 3) * 0.2;
        var hex = Math.floor(brightness * 255).toString(16);
        if (hex.length < 2) hex = "0" + hex;
        context.fillRect(sx, sy, 2, 2, "#" + hex + hex + hex);
      }

      var ox = -camera.x;
      var oy = -camera.y;

      // Platforms
      for (var i = 0; i < platforms.length; i++) {
        var p = platforms[i];
        // Platform body
        context.fillRect(p.x + ox, p.y + oy, p.w, p.h, p.color);
        // Platform top highlight
        context.fillRect(p.x + ox, p.y + oy, p.w, 3, "#7a9a70");
        // Platform bottom shadow
        context.fillRect(p.x + ox, p.y + oy + p.h - 2, p.w, 2, "#2a3721");
      }

      // Goal flag
      // Pole
      context.fillRect(goal.x + ox + 14, goal.y + oy - 20, 4, goal.h + 20, "#cccccc");
      // Flag
      context.fillTriangle(
        goal.x + ox + 18, goal.y + oy - 20,
        goal.x + ox + 48, goal.y + oy - 8,
        goal.x + ox + 18, goal.y + oy + 4,
        "#44ff44"
      );
      // Base
      context.fillRect(goal.x + ox + 6, goal.y + oy + goal.h - 8, 20, 8, "#888888");

      // Coins
      for (var i = 0; i < coins.length; i++) {
        var c = coins[i];
        if (c.collected) continue;
        // Coin glow
        context.fillCircle(c.x + ox + 8, c.y + oy + 8, 10, "#ffdd0020");
        // Coin body
        context.fillCircle(c.x + ox + 8, c.y + oy + 8, 7, "#ffcc00");
        // Coin highlight
        context.fillCircle(c.x + ox + 6, c.y + oy + 6, 3, "#ffee66");
      }

      // Player
      var px = player.x + ox;
      var py = player.y + oy;

      // Player shadow
      context.fillCircle(px + player.w / 2, py + player.h + 2, player.w / 2, "#00000030");

      // Body
      context.fillRect(px + 4, py + 8, 16, 16, "#e74c3c");
      // Head
      context.fillRect(px + 4, py, 16, 12, "#f5cba7");
      // Eyes
      if (player.facing > 0) {
        context.fillRect(px + 14, py + 3, 4, 4, "#ffffff");
        context.fillRect(px + 15, py + 4, 2, 2, "#2c3e50");
      } else {
        context.fillRect(px + 6, py + 3, 4, 4, "#ffffff");
        context.fillRect(px + 7, py + 4, 2, 2, "#2c3e50");
      }

      // Legs (animated)
      if (player.grounded && Math.abs(player.vx) > 0.5) {
        var legOffset = (player.frame % 2 === 0) ? 2 : -2;
        context.fillRect(px + 5, py + 24, 5, 8, "#2c3e50");
        context.fillRect(px + 14, py + 24, 5, 8, "#2c3e50");
        context.fillRect(px + 5 + legOffset, py + 24, 5, 8, "#34495e");
      } else if (!player.grounded) {
        // Airborne legs
        context.fillRect(px + 4, py + 24, 6, 7, "#2c3e50");
        context.fillRect(px + 14, py + 24, 6, 7, "#2c3e50");
      } else {
        // Standing
        context.fillRect(px + 5, py + 24, 5, 8, "#2c3e50");
        context.fillRect(px + 14, py + 24, 5, 8, "#2c3e50");
      }

      // Arms
      if (Math.abs(player.vx) > 0.5) {
        var armSwing = (player.frame % 2 === 0) ? -3 : 3;
        context.fillRect(px, py + 10 + armSwing, 4, 10, "#f5cba7");
        context.fillRect(px + 20, py + 10 - armSwing, 4, 10, "#f5cba7");
      } else {
        context.fillRect(px, py + 10, 4, 10, "#f5cba7");
        context.fillRect(px + 20, py + 10, 4, 10, "#f5cba7");
      }

      // Particles
      for (var i = 0; i < particles.length; i++) {
        var pt = particles[i];
        var alpha = Math.floor(pt.life * 255).toString(16);
        if (alpha.length < 2) alpha = "0" + alpha;
        context.fillRect(pt.x + ox, pt.y + oy, pt.size, pt.size, pt.color + alpha);
      }

      // Game over / win screens
      if (gameState === "dead") {
        context.fillRect(0, 0, W, H, "#00000090");
        context.fillRect(W / 2 - 140, H / 2 - 60, 280, 120, "#1a1a2e");
        context.fillRect(W / 2 - 138, H / 2 - 58, 276, 116, "#16213e");
        context.strokeRect(W / 2 - 140, H / 2 - 60, 280, 120, "#e74c3c", 2);
      }

      if (gameState === "won") {
        context.fillRect(0, 0, W, H, "#00000090");
        context.fillRect(W / 2 - 160, H / 2 - 60, 320, 120, "#1a1a2e");
        context.fillRect(W / 2 - 158, H / 2 - 58, 316, 116, "#16213e");
        context.strokeRect(W / 2 - 160, H / 2 - 60, 320, 120, "#44ff44", 2);

        // Victory stars
        for (var i = 0; i < 5; i++) {
          var sx = W / 2 - 80 + i * 40;
          var sy = H / 2 - 40;
          context.fillCircle(sx, sy, 6, "#ffdd00");
          context.fillCircle(sx - 1, sy - 1, 2, "#ffee66");
        }
      }
    });

    canvas.onKeyDown(function(key) {
      if (key === "R") {
        score = 0; setScore(0);
        level = 1; setLevel(1);
        setGameState("playing");
        buildLevel(1);
      }
    });

    canvas.start();
  }, []);

  return (
    <Box orientation="vertical" expand={true}>
      <Box orientation="horizontal" horizontalAlignment="spaceBetween" spacing={16} className="nav-bar">
        <Label className="card-body">Coins: {score}</Label>
        <Label className="card-body">Level {level} / 10</Label>
      </Box>
      <Canvas id="game" expand={true} />
      <Box orientation="horizontal" horizontalAlignment="center" spacing={16} className="nav-bar">
        <Label className="card-body">Move: A/D or Arrows</Label>
        <Label className="card-body">Jump: W/Up/Space</Label>
        <Label className="card-body">Restart: R</Label>
      </Box>
    </Box>
  );
}

function App() {
  return <Game />;
}

Stigma.onReady(function() {
  Stigma.render("root", App);
});