# Sunflower

A lightweight desktop application framework that pairs **GTK4** with a **JavaScript** engine. Write your UI in declarative XML markup or **JSX components**, style it with CSS, and bring it to life with JavaScript — all without the overhead of a browser engine.

Sunflower is built with [Crystal](https://crystal-lang.org) and uses [QuickJS](https://bellard.org/quickjs/) (via [Medusa](https://github.com/grkek/medusa)) as its embedded JavaScript runtime.

## Why Sunflower?

| | Sunflower | Electron |
|---|---|---|
| Memory (idle) | ~10–30 MB | ~80–150 MB |
| Runtime | QuickJS (~2 MB) | Chromium (~200 MB) |
| UI Layer | Native GTK4 | Embedded browser |
| Language | Crystal + JS | Node.js + JS |

Sunflower gives you a JS-scriptable desktop application with native widgets and a fraction of the resource cost.

## Quick Start

### Prerequisites

- [Crystal](https://crystal-lang.org/install/) (>= 1.10)
- GTK4 development libraries
- GLib development libraries

### Installation

```bash
git clone https://github.com/grkek/sunflower.git
cd sunflower
shards install
./bin/gi-crystal
```

### Hello World

Create a project with the following structure:

```
my-application/
└── dist/
  └── index.html
  └── scripts/
        └── App.jsx
└── src/
  └── application.cr
```

**`application.cr`** — your entry point:

```crystal
require "sunflower"

Log.setup do |c|
  backend = Log::IOBackend.new(STDERR, formatter: Log::ShortFormat, dispatcher: :sync)
  c.bind("*", :debug, backend)
end

builder = Sunflower::Builder.new
builder.build_from_file(File.join(__DIR__, "..", "dist", "index.html"))
```

**`src/index.html`** — your UI:

```xml
<Application applicationId="com.example.hello">
  <Window title="Hello Sunflower" width="400" height="300">
    <Box id="root" orientation="vertical" expand="true" />
  </Window>
  <Script src="scripts/App.jsx" />
</Application>
```

**`src/scripts/App.jsx`** — your App:

```jsx
import Stigma, { useState } from "stigma";

function App() {
  const [count, setCount] = useState(0);

  return (
    <Box orientation="vertical" spacing="12">
      <Label>{"Clicked " + count + " times!"}</Label>
      <Button onPress={function() { setCount(count + 1); }}>
        Click Me
      </Button>
    </Box>
  );
}

Stigma.onReady(function() {
  Stigma.render("root", App);
});
```

Run it:

```bash
GTK_DEBUG=interactive crystal run ./src/application.cr -Dpreview_mt
```

## Three Modes

Sunflower supports three development styles:

### 1. Markup Mode

Define your UI in XML with inline or external scripts. Best for simpler apps or when you want a clear separation between structure and logic. In markup mode, components are accessed through the `__runtime` global which is available without any imports.

```xml
<Application applicationId="com.example.app">
  <StyleSheet src="styles/index.css" />
  <Window title="My App" width="800" height="600">
    <Box orientation="vertical">
      <Label id="title">Hello!</Label>
      <Button id="btn">Click</Button>
    </Box>
  </Window>
  <Script src="scripts/index.js" />
</Application>
```

```javascript
// scripts/index.js — markup mode, no imports needed
__runtime.onReady(function() {
  var btn = __runtime.getComponentById("btn");
  btn.on.press = function() {
    __runtime.getComponentById("title").setText("Clicked!");
  };
});
```

### 2. Component Mode (no JSX)

Use the full Stigma runtime — hooks, virtual DOM, reconciler — without JSX syntax. Write `createElement` calls directly in plain `.js` files. Same power as JSX mode, just without the syntactic sugar.

**`src/index.html`**:

```xml
<Application applicationId="com.example.app">
  <StyleSheet src="styles/index.css" />
  <Window title="My App" width="800" height="600">
    <Box id="root" orientation="vertical" expand="true" />
  </Window>
  <Script src="scripts/App.js" />
</Application>
```

**`scripts/App.js`**:

```javascript
import Stigma, { createElement, useState } from "stigma";

function Counter() {
  const [count, setCount] = useState(0);

  return createElement("Box", { orientation: "vertical", spacing: "12" },
    createElement("Label", { className: "title" }, "Count: " + count),
    createElement("Button", { onPress: function() { setCount(count + 1); } }, "Increment")
  );
}

Stigma.onReady(function() {
  Stigma.render("root", Counter);
});
```

This is useful when you prefer not to use JSX, want to avoid the transpiler, or are generating UI programmatically.

### 3. JSX Mode

Define your UI as composable function components with JSX syntax. This is syntactic sugar over Component Mode — the built-in transpiler converts JSX to `createElement` calls automatically.

**`src/index.html`**:

```xml
<Application applicationId="com.example.app">
  <StyleSheet src="styles/index.css" />
  <Window title="My App" width="800" height="600">
    <Box id="root" orientation="vertical" expand="true" />
  </Window>
  <Script src="scripts/App.jsx" />
</Application>
```

**`scripts/App.jsx`**:

```jsx
import Stigma, { useState } from "stigma";

function Counter() {
  const [count, setCount] = useState(0);

  return (
    <Box orientation="vertical" spacing="12">
      <Label className="title">Count: {count}</Label>
      <Button onPress={function() { setCount(count + 1); }}>
        Increment
      </Button>
    </Box>
  );
}

Stigma.onReady(function() {
  Stigma.render("root", Counter);
});
```

The JSX transpiler runs automatically for `.jsx` files — no build step required. Under the hood, the JSX above compiles to the same `createElement` calls shown in Component Mode.

## Architecture

```
┌─────────────────────────────────────┐
│           JavaScript (QuickJS)      │  Your application logic
├─────────────────────────────────────┤
│           Crystal Bridge            │  Bindings, async promises, IPC
├─────────────────────────────────────┤
│           GTK4 (Native)             │  Rendering, input, styling
└─────────────────────────────────────┘
```

The Crystal bridge connects GTK4 widgets to JavaScript objects. Every widget gets a corresponding JS object with methods and event handlers. Async operations use a promise-based bridge — Crystal spawns a fiber, does the work, and resolves the JS promise when done.

The runtime is split into two layers:

- **`__runtime`** — a lightweight global object that the Crystal bridge writes to. Handles windows, lifecycle callbacks, and component lookups. Always available, no imports needed.
- **`"stigma"` module** — the full JSX runtime including hooks, virtual DOM, reconciler, and rendering. Loaded lazily on first import — markup-only apps never pay for it.

## Markup

Sunflower uses an XML-based markup language. Every application starts with an `<Application>` root containing a `<Window>`.

### Available Components

| Component | Description |
|---|---|
| `Application` | Root element. Requires `applicationId`. |
| `Window` | Application window. Attributes: `title`, `width`, `height`. |
| `Box` | Flex container. Attributes: `orientation` (`vertical`/`horizontal`), `spacing`, `homogeneous`. |
| `Button` | Clickable button. Events: `press`. |
| `Label` | Text display. Supports markup. |
| `Entry` | Text input field. Events: `change`. Attributes: `inputType="password"`. |
| `Image` | Displays images from local paths or URLs. |
| `ListBox` | Scrollable list container. |
| `ScrolledWindow` | Scrollable container for overflow content. |
| `Frame` | Visual grouping container with optional label. |
| `Tab` | Tabbed container. |
| `Switch` | Toggle switch. |
| `Canvas` | GPU-accelerated 2D drawing surface for games and visualizations. |
| `HorizontalSeparator` | Horizontal divider line. |
| `VerticalSeparator` | Vertical divider line. |

All components support self-closing syntax: `<Box />`, `<Entry />`, `<StyleSheet src="..." />`.

### Attributes

Every component supports:

- `id` — Unique identifier for JS access
- `className` — CSS class for styling
- `expand` — Whether the widget expands to fill available space
- `horizontalAlignment` — `"center"`, `"start"`, `"end"`, `"fill"`
- `verticalAlignment` — `"center"`, `"start"`, `"end"`, `"fill"`

### Scripts

Embed JavaScript inline or load from a file:

```xml
<!-- Inline -->
<Script>
  console.log("Hello from Sunflower!");
</Script>

<!-- External JS -->
<Script src="scripts/index.js" />

<!-- External JSX (auto-transpiled) -->
<Script src="scripts/App.jsx" />
```

### Stylesheets

Style your application with GTK CSS:

```xml
<!-- Inline -->
<StyleSheet>
  .my-button {
    background-color: #3584e4;
    color: white;
    border-radius: 6px;
    padding: 8px 16px;
  }
</StyleSheet>

<!-- External -->
<StyleSheet src="styles/index.css" />
```

## JavaScript API

### ES Module Imports

Sunflower's standard library is available as ES module imports:

```javascript
import Stigma, { useState, useEffect } from "stigma";
import { Canvas } from "canvas";
import { read, write, exists, mkdir } from "fs";
import { get, post, download } from "http";
```

The module loader checks built-in modules first, then falls back to loading `.js` files from disk for user modules.

### Import Styles

The `"stigma"` module supports multiple import patterns, similar to React:

```javascript
// Default import — the full Stigma object
import Stigma from "stigma";
Stigma.render("root", App);
Stigma.useState(0);
Stigma.onReady(function() { });

// Named imports — destructured
import { useState, useEffect, render, onReady } from "stigma";

// Both (recommended for JSX)
import Stigma, { useState, useEffect } from "stigma";
```

### Available Imports from `"stigma"`

| Export | Description |
|---|---|
| `createElement` | Virtual DOM node constructor (used by JSX transpiler) |
| `Fragment` | Fragment component for grouping without a wrapper |
| `useState` | State hook for function components |
| `useEffect` | Effect hook for side effects |
| `render` | Mount a component into a container |
| `onReady` | Register a callback for when the app is ready |
| `onExit` | Register a callback for when the app exits |
| `getWindow` | Get a window object by ID |
| `getComponentById` | Get a component by ID (optionally scoped to a window) |
| `findComponentById` | Search all windows for a component |
| `default` | The full `Stigma` object (includes `windows`, `mainWindow`, `windowIds`, `componentIds`) |

### The `__runtime` Object

The `__runtime` global is the internal bridge between Crystal and JavaScript. It's always available without imports and is useful in markup mode scripts:

```javascript
// Component access
var btn = __runtime.getComponentById("myButton");
var label = __runtime.getComponentById("title", "Main");

// Window access
__runtime.windows["Main"];
__runtime.getWindow("Main");

// Lifecycle
__runtime.onReady(function() { });
__runtime.onExit(function() { });
```

In JSX mode, prefer importing from `"stigma"` instead of using `__runtime` directly.

### Event Handlers

Attach handlers through the `on` property:

```javascript
import Stigma from "stigma";

Stigma.getComponentById("myButton").on.press = function() {
  console.log("Button pressed!");
};

Stigma.getComponentById("myEntry").on.change = function(text) {
  console.log("Text changed: " + text);
};
```

### Component Methods

#### Button

```javascript
var btn = Stigma.getComponentById("myButton");
btn.setText("New Label");
```

#### Label

```javascript
var label = Stigma.getComponentById("myLabel");
label.setText("Plain text");
label.setLabel("Text with <b>markup</b>");
label.getText();
label.setWrap(true);
label.setEllipsize("end");
label.setXAlign(0.5);
label.setYAlign(0.5);
```

#### Entry

```javascript
var entry = Stigma.getComponentById("myEntry");
entry.setText("Default value");
var text = entry.getText();
entry.isPassword(true);
```

#### Image

```javascript
var img = Stigma.getComponentById("myImage");

// Load from URL (async)
await img.setResourcePath("https://example.com/photo.jpg");

// Load from local file
await img.setResourcePath("/path/to/image.png");

// Set content fit
img.setContentFit("cover"); // "fill", "contain", "cover", "none"
```

#### Box

```javascript
var box = Stigma.getComponentById("myBox");
box.append("childComponentId");
box.destroyChildren();
```

#### ListBox

```javascript
var list = Stigma.getComponentById("myList");
list.removeAll();
```

#### Window

```javascript
import Stigma from "stigma";

var win = Stigma.mainWindow;
win.setTitle("New Title");
win.maximize();
win.minimize();
```

#### Universal Methods

Available on all components:

```javascript
var comp = Stigma.getComponentById("any");
comp.setVisible(false);
comp.addCssClass("highlighted");
comp.removeCssClass("highlighted");
```

### Component State

Every component has a lazy `state` getter that reads the current widget state from GTK:

```javascript
var btn = Stigma.getComponentById("myButton");
console.log(btn.state);
```

### Lifecycle

```javascript
import Stigma from "stigma";

// Run code when the application is ready (all components mounted)
Stigma.onReady(function() {
  console.log("I am ready!");
});

// Run code on exit (supports multiple callbacks)
Stigma.onExit(function() {
  console.log("Goodbye!");
});
```

### Async / Await

Sunflower has full async/await support. Any Crystal binding that does I/O returns a JS Promise that you can `await`:

```javascript
import Stigma from "stigma";

Stigma.onReady(async function() {
  await img.setResourcePath("https://example.com/photo.jpg");
  console.log("Image loaded!");
});
```

## JSX Components

### Setup

Create a minimal HTML shell with a root container, then write your UI in `.jsx` files:

```xml
<Application applicationId="com.example.app">
  <StyleSheet src="styles/index.css" />
  <Window title="My App" width="800" height="600">
    <Box id="root" orientation="vertical" expand="true" />
  </Window>
  <Script src="scripts/App.jsx" />
</Application>
```

### Function Components

Components are plain functions that return JSX. JSX files must import from `"stigma"` — the transpiler converts JSX syntax to `createElement()` calls:

```jsx
import Stigma from "stigma";

function Greeting({ name }) {
  return (
    <Box orientation="vertical">
      <Label className="title">Hello, {name}!</Label>
    </Box>
  );
}
```

### useState

Manage component state with `useState`:

```jsx
import Stigma, { useState } from "stigma";

function Counter() {
  const [count, setCount] = useState(0);

  return (
    <Box orientation="vertical">
      <Label>Count: {count}</Label>
      <Button onPress={function() { setCount(count + 1); }}>+1</Button>
      <Button onPress={function() { setCount(0); }}>Reset</Button>
    </Box>
  );
}
```

### useEffect

Run side effects after render:

```jsx
import Stigma, { useState, useEffect } from "stigma";

function Timer() {
  const [seconds, setSeconds] = useState(0);

  useEffect(function() {
    console.log("Timer mounted");
    return function() {
      console.log("Timer unmounted");
    };
  }, []);

  return <Label>Elapsed: {seconds}s</Label>;
}
```

### Composing Components

Nest components and pass props:

```jsx
import Stigma from "stigma";

function UserCard({ name, email }) {
  return (
    <Box orientation="vertical" className="card">
      <Label className="name">{name}</Label>
      <Label className="email">{email}</Label>
    </Box>
  );
}

function App() {
  return (
    <Box orientation="vertical">
      <UserCard name="Giorgi" email="giorgi@example.com" />
      <UserCard name="Alice" email="alice@example.com" />
    </Box>
  );
}

Stigma.onReady(function() {
  Stigma.render("root", App);
});
```

### Conditional Rendering

```jsx
import Stigma, { useState } from "stigma";

function App() {
  const [loggedIn, setLoggedIn] = useState(false);

  if (loggedIn) {
    return <Label>Welcome back!</Label>;
  }

  return (
    <Button onPress={function() { setLoggedIn(true); }}>
      Sign In
    </Button>
  );
}
```

### Event Handlers in JSX

```jsx
<Button onPress={handleClick}>Click Me</Button>
<Entry onChange={function(text) { setQuery(text); }} />
```

### Fragments

Group elements without adding a wrapper widget:

```jsx
// Named tag
<Fragment>
  <Label>First</Label>
  <Label>Second</Label>
</Fragment>

// Shorthand syntax
<>
  <Label>First</Label>
  <Label>Second</Label>
</>
```

### Mounting

Mount your root component into a container defined in the HTML:

```jsx
import Stigma from "stigma";

Stigma.onReady(function() {
  Stigma.render("root", App);
});
```

## 2D Game Engine

Sunflower includes a GPU-accelerated 2D Canvas for building games and interactive visualizations. Rendering is done through OpenGL via GTK4's `GLArea` widget with batched draw calls.

### Getting Started

Add a `<Canvas>` element to your JSX layout and import the `Canvas` class:

```jsx
import { Canvas } from "canvas";
import { useEffect } from "stigma";

function MyGame() {
  useEffect(function() {
    const canvas = new Canvas("game", {
      width: 800,
      height: 600,
      framesPerSecond: 60
    });

    canvas.onDraw(function(context) {
      context.clear("#000000");
      context.fillRect(100, 100, 50, 50, "#ff0000");
    });

    canvas.start();
  }, []);

  return (
    <Box orientation="vertical" expand="true">
      <Canvas id="game" expand="true" />
    </Box>
  );
}
```

### Canvas Constructor

```javascript
const canvas = new Canvas(id, options);
```

| Option | Type | Default | Description |
|---|---|---|---|
| `width` | number | 800 | Requested width in logical pixels |
| `height` | number | 600 | Requested height in logical pixels |
| `framesPerSecond` | number | 60 | Target frame rate |

The actual canvas size may differ from the requested size when `expand="true"` is set — use `canvas.getWidth()` and `canvas.getHeight()` to read the real dimensions.

### Game Loop

The canvas runs two callbacks per frame at the configured frame rate:

```javascript
// Called before drawing — update game state here
canvas.onUpdate(function(dt) {
  // dt is the time since last frame in seconds
  player.x += player.speed * dt;
});

// Called after update — draw your frame here
canvas.onDraw(function(context) {
  context.clear("#000000");
  context.fillRect(player.x, player.y, 32, 32, "#00ff00");
});

// Start the game loop
canvas.start();

// Stop the game loop
canvas.stop();
```

### Drawing API

The context object passed to `onDraw` provides these drawing primitives:

```javascript
canvas.onDraw(function(context) {
  // Clear the entire canvas
  context.clear("#000000");

  // Filled rectangle
  context.fillRect(x, y, width, height, color);

  // Stroked rectangle (outline only)
  context.strokeRect(x, y, width, height, color, lineWidth);

  // Filled circle
  context.fillCircle(centerX, centerY, radius, color);

  // Stroked circle (outline only)
  context.strokeCircle(centerX, centerY, radius, color, lineWidth);

  // Line between two points
  context.drawLine(x1, y1, x2, y2, color, lineWidth);

  // Filled triangle
  context.fillTriangle(x1, y1, x2, y2, x3, y3, color);

  // Text (placeholder — renders as a rectangle until font atlas is implemented)
  context.fillText(text, x, y, color, fontSize);
});
```

All colors are hex strings with optional alpha: `"#ff0000"`, `"#ff000080"` (50% transparent red).

### Input

```javascript
// Keyboard — poll in onUpdate
canvas.onUpdate(function(dt) {
  if (canvas.isKeyDown("w")) player.y -= speed;
  if (canvas.isKeyDown("s")) player.y += speed;
  if (canvas.isKeyDown("Left")) player.x -= speed;
  if (canvas.isKeyDown("Right")) player.x += speed;
});

// Keyboard — event callbacks
canvas.onKeyDown(function(key) {
  console.log("Pressed: " + key);
});

canvas.onKeyUp(function(key) {
  console.log("Released: " + key);
});

// Mouse — poll in onUpdate
canvas.onUpdate(function(dt) {
  var mx = canvas.mouseX();
  var my = canvas.mouseY();
  var pressed = canvas.isMouseDown();
});

// Mouse — event callbacks
canvas.onMouseDown(function(x, y) { });
canvas.onMouseUp(function(x, y) { });
canvas.onMouseMove(function(x, y) { });
```

Key names follow GDK naming: `"w"`, `"s"`, `"Up"`, `"Down"`, `"Left"`, `"Right"`, `"space"`, `"Return"`, etc.

### Responsive Canvas

The canvas automatically adapts to HiDPI displays (Retina). Use `getWidth()` and `getHeight()` to read the actual logical dimensions and make your game responsive to window resizing:

```javascript
canvas.onUpdate(function(dt) {
  var W = canvas.getWidth();
  var H = canvas.getHeight();

  // Clamp player to canvas bounds
  player.x = Math.max(0, Math.min(W - player.size, player.x));
  player.y = Math.max(0, Math.min(H - player.size, player.y));
});

canvas.onDraw(function(context) {
  var W = canvas.getWidth();
  var H = canvas.getHeight();

  context.clear("#000");
  // Center line
  context.drawLine(W / 2, 0, W / 2, H, "#333", 2);
});
```

## Built-in Modules

Sunflower's standard library is available as ES module imports.

### `stigma` — Runtime & Hooks

The Stigma module is the JSX runtime. It loads lazily on first import — markup-only apps never pay for the reconciler, hooks, or virtual DOM overhead.

```javascript
import Stigma, { useState, useEffect } from "stigma";

// State management
const [value, setValue] = useState(initialValue);

// Side effects
useEffect(function() {
  // setup
  return function() { /* cleanup */ };
}, [dependencies]);

// Mount a component
Stigma.render("containerId", MyComponent);

// Lifecycle
Stigma.onReady(function() { /* app is ready */ });
Stigma.onExit(function() { /* app is closing */ });

// Window & component access
Stigma.mainWindow;
Stigma.getComponentById("myButton");
Stigma.windows;
```

### `fs` — File System

```javascript
import { read, write, append, exists, remove, mkdir, readdir, stat, writeBytes, readBytes } from "fs";

// Read / write / append
const content = await read("/path/to/file.txt");
await write("/path/to/file.txt", "Hello!");
await append("/path/to/log.txt", "New entry\n");

// Check existence and delete
const exists = await exists("/path/to/file.txt");
await remove("/path/to/file.txt");

// Directories
await mkdir("/path/to/new/dir");
const entries = await readdir("/path/to/dir");

// File info
const info = await stat("/path/to/file.txt");
console.log(info.size);
console.log(info.isFile);
console.log(info.isDirectory);
console.log(info.modifiedAt);

// Binary data
await writeBytes("/path/to/file.bin", new Uint8Array([0x89, 0x50, 0x4E, 0x47]));
const bytes = await readBytes("/path/to/file.bin");
```

### `http` — Networking

```javascript
import { get, post, put, patch, del, request, download } from "http";

// GET
const res = await get("https://api.example.com/data");
console.log(res.status);
console.log(res.body);
console.log(res.headers);

// GET with headers
const res = await get("https://api.example.com/data", {
  "Authorization": "Bearer token123"
});

// POST JSON
const res = await post("https://api.example.com/users",
  { name: "Giorgi" },
  { "Content-Type": "application/json" }
);

// PUT, PATCH, DELETE
await put(url, body, headers);
await patch(url, body, headers);
await del(url, headers);

// Generic request
const res = await request({
  url: "https://api.example.com/resource",
  method: "PATCH",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ updated: true })
});

// Download a file
const dl = await download("https://example.com/image.png", "/tmp/image.png");
console.log("Downloaded " + dl.bytes + " bytes to " + dl.path);
```

### `canvas` — 2D Game Engine

```javascript
import { Canvas } from "canvas";

const canvas = new Canvas("myCanvas", { width: 800, height: 600, framesPerSecond: 60 });

canvas.onUpdate(function(dt) { /* game logic */ });
canvas.onDraw(function(context) { /* rendering */ });
canvas.start();
```

See the [2D Game Engine](#2d-game-engine) section for the full API reference.

### Error Handling

All async module calls return an `error` field on failure instead of throwing:

```javascript
import { get } from "http";
import { read } from "fs";

const res = await get("https://invalid.example.com");
if (res.error) {
  console.error("Request failed: " + res.error);
}

const content = await read("/nonexistent/file.txt");
if (content.error) {
  console.error("Read failed: " + content.error);
}
```

## Console

Standard `console` methods are available:

```javascript
console.log("Info message");
console.info("Same as log");
console.debug("Same as log");
console.warn("Warning message");   // stderr with [WARN] prefix
console.error("Error message");    // stderr with [ERROR] prefix

// Objects are automatically JSON-serialized
console.log({ key: "value" });     // {"key":"value"}
```

## IPC

Sunflower exposes a UNIX socket for inter-process communication. External processes can send JSON messages to evaluate JavaScript in the running application.

### Message Format

```json
{
  "id": "unique-request-id",
  "directory": "/path/to/project",
  "file": "src/index.html",
  "line": 1,
  "sourceCode": "__runtime.getComponentById('title').setText('Updated from IPC!')"
}
```

| Field | Type | Description |
|---|---|---|
| `id` | `string` | Unique identifier for the request |
| `directory` | `string` | Project directory path |
| `file` | `string` | Source file that triggered the request |
| `line` | `int` | Line number in the source file |
| `sourceCode` | `string` | JavaScript code to evaluate |

### Example

```bash
echo '{"id":"1","directory":".","file":"repl","line":1,"sourceCode":"console.log(__runtime.componentIds)"}' \
  | socat - UNIX-CONNECT:/tmp/<socket-id>.sock
```

The socket path is logged on startup. IPC evaluates code in the global scope, so use `__runtime` for component and window access.

## How It Works

### The Two-Layer Runtime

Sunflower's JavaScript runtime is split into two layers:

- **`__runtime`** (global) — The Crystal bridge target. A lightweight object created eagerly at startup that holds the window registry, lifecycle callbacks, and component lookup functions. Crystal writes directly into `__runtime.windows`, calls `__runtime.flushReady()`, and binds window methods here. This is always available, even in markup-only apps.

- **`"stigma"` module** (lazy) — The full JSX runtime including `createElement`, hooks (`useState`, `useEffect`), the virtual DOM reconciler, and the `render` function. This module is only loaded when user code writes `import ... from "stigma"`. Markup-only apps that never import it pay zero cost for the reconciler.

### The Promise Bridge

Sunflower's async system bridges Crystal fibers and JavaScript promises:

1. A JS call (e.g. `img.setResourcePath(url)`) invokes a Crystal binding
2. Crystal generates a unique promise ID and spawns a fiber for the async work
3. The binding returns the promise ID to JS, which wraps it in a `Promise`
4. The Crystal fiber completes the work (HTTP request, file I/O, etc.)
5. It calls `resolve_promise(id, value)` to queue the result
6. A GLib timer (running at ~60fps) picks up resolved promises, passes values to JS, and drains the QuickJS job queue

This gives you true non-blocking async in JS while all heavy lifting happens in Crystal fibers — no thread pools, no callback hell, and the GTK main loop never blocks.

### The Module Loader

Sunflower uses a custom ES module loader that integrates with QuickJS's native `import`/`export` system. When you write `import { useState } from "stigma"`, QuickJS calls into a C++ bridge that checks Sunflower's built-in module registry first. If the module isn't registered, it falls back to loading `.js` files from disk with path resolution relative to the importing file.

Built-in modules register their JavaScript source at startup. The source uses standard ES module syntax (`export class`, `export function`) and calls into native Crystal bindings under the hood.

### The Job Drain

A GLib timer fires every 16ms to:

1. Yield to Crystal's fiber scheduler (so spawned fibers can run)
2. Flush any resolved promises into JavaScript
3. Drain the QuickJS job queue (so `await` continuations execute)

This is the heartbeat that keeps async flowing between Crystal and JS without blocking the UI.

### The JSX Transpiler

When a `.jsx` file is loaded, Sunflower's built-in transpiler converts JSX syntax to `createElement()` calls before passing the code to QuickJS. No external build tools needed.

```jsx
// Input
<Box orientation="vertical">
  <Label className="title">Hello</Label>
</Box>

// Output
Stigma.createElement("Box", { orientation: "vertical" },
  Stigma.createElement("Label", { className: "title" }, "Hello")
)
```

The transpiled `Stigma.createElement` references resolve through the user's `import Stigma from "stigma"` — the transpiler only handles syntax transformation, not imports.

Custom components (uppercase names not matching built-in widgets) are emitted as function references: `<MyComponent />` becomes `Stigma.createElement(MyComponent, null)`.

Fragment shorthand `<>...</>` is transpiled to `Stigma.createElement(Fragment, null, ...)`.

### The Reconciler

In JSX mode, the Stigma module includes a virtual DOM reconciler that diffs old and new component trees. When state changes:

1. The component function re-runs, producing a new virtual DOM tree
2. The reconciler walks old and new trees side by side
3. Same element type → updates the existing GTK widget in-place (props, text, event handlers)
4. Different type → destroys the old widget and creates a new one
5. Entry widgets are never overwritten during updates to preserve user input

This means `useState` triggers efficient in-place updates — not a full tear-down and rebuild.

### The 2D Renderer

The Canvas module uses a batched OpenGL renderer on top of GTK4's `GLArea`. Each frame, JavaScript draw commands are collected into a command buffer (clear, fillRect, fillCircle, etc.). When the GLArea renders, the Crystal side walks the command buffer and pushes vertices into a single VBO, drawing everything in one or a few `glDrawArrays` calls.

The renderer uses an orthographic projection with `(0,0)` at the top-left corner. HiDPI displays are handled automatically — the viewport scales to physical pixels while the projection stays in logical coordinates, so game code doesn't need to know about Retina scaling.

## Contributing

1. Fork it (<https://github.com/grkek/sunflower/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Giorgi Kavrelishvili](https://github.com/grkek) - creator and maintainer