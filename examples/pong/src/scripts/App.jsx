import { Canvas } from "canvas";
import Stigma, { useState, useEffect } from "stigma";

function PongGame() {
  let scores = useState([0, 0]);
  let setScores = scores[1];
  scores = scores[0];

  let gameOver = useState(false);
  let setGameOver = gameOver[1];
  gameOver = gameOver[0];

  let ball = { x: 450, y: 325, vx: 4, vy: 3, size: 10 };

  let paddles = {
    left: { y: 200, h: 80, w: 12, speed: 5 },
    right: { y: 200, h: 80, w: 12, speed: 5 }
  };

  let WINNING_SCORE = 5;

  useEffect(function() {
    const canvas = new Canvas("pong", { width: 900, height: 650, framesPerSecond: 60 });

    canvas.onUpdate(function(dt) {
      if (gameOver) return;

      let W = canvas.getWidth();
      let H = canvas.getHeight();

      if (canvas.isKeyDown("W")) paddles.left.y -= paddles.left.speed;
      if (canvas.isKeyDown("S")) paddles.left.y += paddles.left.speed;
      if (canvas.isKeyDown("Up")) paddles.right.y -= paddles.right.speed;
      if (canvas.isKeyDown("Down")) paddles.right.y += paddles.right.speed;

      paddles.left.y = Math.max(0, Math.min(H - paddles.left.h, paddles.left.y));
      paddles.right.y = Math.max(0, Math.min(H - paddles.right.h, paddles.right.y));

      ball.x += ball.vx;
      ball.y += ball.vy;

      if (ball.y <= 0 || ball.y >= H - ball.size) ball.vy = -ball.vy;

      if (ball.x <= 30 + paddles.left.w &&
          ball.y + ball.size >= paddles.left.y &&
          ball.y <= paddles.left.y + paddles.left.h) {
        ball.vx = Math.abs(ball.vx) * 1.05;
        var hitPos = (ball.y - paddles.left.y) / paddles.left.h;
        ball.vy = (hitPos - 0.5) * 8;
      }

      if (ball.x >= W - 30 - paddles.right.w - ball.size &&
          ball.y + ball.size >= paddles.right.y &&
          ball.y <= paddles.right.y + paddles.right.h) {
        ball.vx = -Math.abs(ball.vx) * 1.05;
        let hitPos = (ball.y - paddles.right.y) / paddles.right.h;
        ball.vy = (hitPos - 0.5) * 8;
      }

      ball.vx = Math.max(-12, Math.min(12, ball.vx));
      ball.vy = Math.max(-8, Math.min(8, ball.vy));

      if (ball.x < 0) {
        scores[1]++;
        setScores([scores[0], scores[1]]);
        resetBall(W, H);
      } else if (ball.x > W) {
        scores[0]++;
        setScores([scores[0], scores[1]]);
        resetBall(W, H);
      }

      if (scores[0] >= WINNING_SCORE || scores[1] >= WINNING_SCORE) {
        setGameOver(true);
      }
    });

    canvas.onDraw(function(context) {
      let W = canvas.getWidth();
      let H = canvas.getHeight();

      context.clear("#0a0a14");

      for (var i = 0; i < 20; i++) {
        context.fillRect(W / 2 - 1, i * (H / 20) + 5, 2, H / 40, "#1a1a2e");
      }

      context.fillRect(20, paddles.left.y, paddles.left.w, paddles.left.h, "#5a7aff");
      context.fillRect(W - 20 - paddles.right.w, paddles.right.y, paddles.right.w, paddles.right.h, "#ff5a7a");

      context.fillRect(20, paddles.left.y, 2, paddles.left.h, "#8aaaff");
      context.fillRect(W - 22, paddles.right.y, 2, paddles.right.h, "#ff8aaa");

      context.fillCircle(ball.x + ball.size / 2, ball.y + ball.size / 2, ball.size / 2, "#ffffff");
      context.fillCircle(ball.x + ball.size / 2 - ball.vx, ball.y + ball.size / 2 - ball.vy, ball.size / 3, "#ffffff40");
      context.fillCircle(ball.x + ball.size / 2 - ball.vx * 2, ball.y + ball.size / 2 - ball.vy * 2, ball.size / 4, "#ffffff20");

      context.fillText(String(scores[0]), W / 2 - 60, 20, "#5a7aff", 48);
      context.fillText(String(scores[1]), W / 2 + 30, 20, "#ff5a7a", 48);

      context.fillText("W/S", 30, H - 20, "#333355", 12);
      context.fillText("Up/Down", W - 90, H - 20, "#553333", 12);

      if (gameOver) {
        context.fillRect(0, 0, W, H, "#00000080");
        let winner = scores[0] >= WINNING_SCORE ? "Blue" : "Red";
        context.fillText(winner + " Wins!", W / 2 - 80, H / 2 - 30, "#ffffff", 36);
        context.fillText("Press R to restart", W / 2 - 80, H / 2 + 20, "#666688", 16);
      }
    });

    canvas.onKeyDown(function(key) {
      if (key === "r" || key === "R") {
        scores = [0, 0];
        setScores([0, 0]);
        setGameOver(false);
        resetBall(canvas.getWidth(), canvas.getHeight());
      }
    });

    canvas.start();
  }, []);

  function resetBall(W, H) {
    ball.x = W / 2;
    ball.y = H / 2;
    ball.vx = (Math.random() > 0.5 ? 4 : -4);
    ball.vy = (Math.random() * 4 - 2);
  }

  return (
    <Box orientation="vertical" expand={true}>
      <Box orientation="horizontal" horizontalAlignment="center" spacing={32} className="header">
        <Label className="score-blue">{String(scores[0])}</Label>
        <Label className="app-name">Pong</Label>
        <Label className="score-red">{String(scores[1])}</Label>
      </Box>
      <Canvas id="pong" expand={true} />
      <Box orientation="horizontal" horizontalAlignment="center" spacing={8} className="nav-bar">
        <Label className="card-body">Blue: W/S</Label>
        <Label className="card-body">Red: Up/Down</Label>
        <Label className="card-body">Restart: R</Label>
      </Box>
    </Box>
  );
}

function App() {
  return <PongGame />;
}

Stigma.onReady(function() {
  Stigma.render("root", App);
});