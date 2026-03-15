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

**`src/scripts/App.jsx`** - your App:
```jsx
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

$.onReady(function() {
  $.render("root", App);
});
```

Run it:

```bash
GTK_DEBUG=interactive crystal run ./src/application.cr -Dpreview_mt
```

## Two Modes

Sunflower supports two development styles:

### 1. Markup Mode

Define your UI in XML with inline or external scripts. Best for simpler apps or when you want a clear separation between structure and logic.

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

### 2. JSX Mode

Define your UI as composable function components with `useState`, `useEffect`, and a virtual DOM reconciler. The markup becomes a minimal shell.

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

$.onReady(function() {
  $.render("root", Counter);
});
```

The JSX transpiler runs automatically for `.jsx` files — no build step required.

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

### The `$` Object

The global `$` object is your entry point to the application.

```javascript
// Access the main window
$.mainWindow;

// Get a component by ID
var btn = $.getComponentById("myButton");

// Get a component from a specific window
var label = $.getComponentById("title", "Main");

// List all component IDs
console.log($.componentIds);

// List all window IDs
console.log($.windowIds);
```

### Event Handlers

Attach handlers through the `on` property:

```javascript
$.getComponentById("myButton").on.press = function() {
  console.log("Button pressed!");
};

$.getComponentById("myEntry").on.change = function(text) {
  console.log("Text changed: " + text);
};
```

### Component Methods

#### Button

```javascript
var btn = $.getComponentById("myButton");
btn.setText("New Label");
```

#### Label

```javascript
var label = $.getComponentById("myLabel");
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
var entry = $.getComponentById("myEntry");
entry.setText("Default value");
var text = entry.getText();
entry.isPassword(true);
```

#### Image

```javascript
var img = $.getComponentById("myImage");

// Load from URL (async)
await img.setResourcePath("https://example.com/photo.jpg");

// Load from local file
await img.setResourcePath("/path/to/image.png");

// Set content fit
img.setContentFit("cover"); // "fill", "contain", "cover", "none"
```

#### Box

```javascript
var box = $.getComponentById("myBox");
box.append("childComponentId");
box.destroyChildren();
```

#### ListBox

```javascript
var list = $.getComponentById("myList");
list.removeAll();
```

#### Window

```javascript
var win = $.mainWindow;
win.setTitle("New Title");
win.maximize();
win.minimize();
```

#### Universal Methods

Available on all components:

```javascript
var comp = $.getComponentById("any");
comp.setVisible(false);
comp.addCssClass("highlighted");
comp.removeCssClass("highlighted");
```

### Component State

Every component has a lazy `state` getter that reads the current widget state from GTK:

```javascript
var btn = $.getComponentById("myButton");
console.log(btn.state);
```

### Lifecycle

```javascript
// Run code when the application is ready (all components mounted)
$.onReady(function() {
  console.log("I am ready!");
});

// Run code on exit (supports multiple callbacks)
$.onExit(function() {
  console.log("Goodbye!");
});
```

### Async / Await

Sunflower has full async/await support. Any Crystal binding that does I/O returns a JS Promise that you can `await`:

```javascript
$.onReady(async function() {
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

Components are plain functions that return JSX:

```jsx
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

$.onReady(function() {
  $.render("root", App);
});
```

### Conditional Rendering

```jsx
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

### Mounting

Mount your root component into a container defined in the HTML:

```javascript
$.onReady(function() {
  $.render("root", App);
});
```

## Built-in Modules

### `$.fs` — File System

```javascript
// Read / write / append
var content = await $.fs.read("/path/to/file.txt");
await $.fs.write("/path/to/file.txt", "Hello!");
await $.fs.append("/path/to/log.txt", "New entry\n");

// Check existence and delete
var exists = await $.fs.exists("/path/to/file.txt");
await $.fs.delete("/path/to/file.txt");

// Directories
await $.fs.mkdir("/path/to/new/dir");
var entries = await $.fs.readdir("/path/to/dir");

// File info
var info = await $.fs.statistics("/path/to/file.txt");
console.log(info.size);
console.log(info.isFile);
console.log(info.isDirectory);
console.log(info.modifiedAt);

// Binary data
await $.fs.writeBytes("/path/to/file.bin", new Uint8Array([0x89, 0x50, 0x4E, 0x47]));
var bytes = await $.fs.readBytes("/path/to/file.bin");
```

### `$.http` — Networking

```javascript
// GET
var res = await $.http.get("https://api.example.com/data");
console.log(res.status);
console.log(res.body);
console.log(res.headers);

// GET with headers
var res = await $.http.get("https://api.example.com/data", {
  "Authorization": "Bearer token123"
});

// POST JSON
var res = await $.http.post("https://api.example.com/users",
  JSON.stringify({ name: "Giorgi" }),
  { "Content-Type": "application/json" }
);

// PUT, PATCH, DELETE
await $.http.put(url, body, headers);
await $.http.patch(url, body, headers);
await $.http.delete(url, headers);

// Generic request
var res = await $.http.request({
  url: "https://api.example.com/resource",
  method: "PATCH",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ updated: true })
});

// Download a file
var dl = await $.http.download("https://example.com/image.png", "/tmp/image.png");
console.log("Downloaded " + dl.bytes + " bytes to " + dl.path);
```

### Error Handling

All async module calls return an `error` field on failure instead of throwing:

```javascript
var res = await $.http.get("https://invalid.example.com");
if (res.error) {
  console.error("Request failed: " + res.error);
}

var content = await $.fs.read("/nonexistent/file.txt");
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
  "sourceCode": "$.getComponentById('title').setText('Updated from IPC!')"
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
echo '{"id":"1","directory":".","file":"repl","line":1,"sourceCode":"console.log($.componentIds)"}' \
  | socat - UNIX-CONNECT:/tmp/<socket-id>.sock
```

The socket path is logged on startup.

## How It Works

### The Promise Bridge

Sunflower's async system bridges Crystal fibers and JavaScript promises:

1. A JS call (e.g. `img.setResourcePath(url)`) invokes a Crystal binding
2. Crystal generates a unique promise ID and spawns a fiber for the async work
3. The binding returns the promise ID to JS, which wraps it in a `Promise`
4. The Crystal fiber completes the work (HTTP request, file I/O, etc.)
5. It calls `resolve_promise(id, value)` to queue the result
6. A GLib timer (running at ~60fps) picks up resolved promises, passes values to JS, and drains the QuickJS job queue

This gives you true non-blocking async in JS while all heavy lifting happens in Crystal fibers — no thread pools, no callback hell, and the GTK main loop never blocks.

### The Job Drain

A GLib timer fires every 16ms to:

1. Yield to Crystal's fiber scheduler (so spawned fibers can run)
2. Flush any resolved promises into JavaScript
3. Drain the QuickJS job queue (so `await` continuations execute)

This is the heartbeat that keeps async flowing between Crystal and JS without blocking the UI.

### The JSX Transpiler

When a `.jsx` file is loaded, Sunflower's built-in transpiler converts JSX syntax to `h()` function calls before passing the code to QuickJS. No external build tools needed.

```jsx
// Input
<Box orientation="vertical">
  <Label className="title">Hello</Label>
</Box>

// Output
h("Box", { orientation: "vertical" },
  h("Label", { className: "title" }, "Hello")
)
```

Custom components (uppercase names not matching built-in widgets) are emitted as function references: `<MyComponent />` becomes `h(MyComponent, null)`.

### The Reconciler

In JSX mode, the Seed runtime includes a virtual DOM reconciler that diffs old and new component trees. When state changes:

1. The component function re-runs, producing a new virtual DOM tree
2. The reconciler walks old and new trees side by side
3. Same element type → updates the existing GTK widget in-place (props, text, event handlers)
4. Different type → destroys the old widget and creates a new one
5. Entry widgets are never overwritten during updates to preserve user input

This means `useState` triggers efficient in-place updates — not a full tear-down and rebuild.

## Contributing

1. Fork it (<https://github.com/grkek/sunflower/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Giorgi Kavrelishvili](https://github.com/grkek) - creator and maintainer