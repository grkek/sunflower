# Sunflower

A lightweight desktop application framework that pairs **GTK4** with a **JavaScript** engine. Write your UI in a declarative XML markup, style it with CSS, and bring it to life with JavaScript — all without the overhead of a browser engine.

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
├── application.cr
└── src/
    └── index.html
```

**`application.cr`** — your entry point:

```crystal
require "sunflower"

Log.setup do |c|
  backend = Log::IOBackend.new(STDERR, formatter: Log::ShortFormat, dispatcher: :sync)
  c.bind("*", :debug, backend)
end

builder = Sunflower::Builder.new
builder.build_from_file(File.join(__DIR__, "src", "index.html"))
```

**`src/index.html`** — your UI:

```xml
<Application applicationId="com.example.hello">
  <Window title="Hello Sunflower" width="400" height="300">
    <Box orientation="vertical" spacing="12">
      <Label id="greeting">Hello, World!</Label>
      <Button id="clickMe">Click Me</Button>
    </Box>
  </Window>

  <Script>
    var count = 0;

    $.getComponentById("clickMe").on.press = function() {
      count++;
      $.getComponentById("greeting").setText("Clicked " + count + " times!");
    };
  </Script>
</Application>
```

Run it:

```bash
# The interactive GTK dashboard will spawn next to your window
# so that you can inspect the components.
GTK_DEBUG=interactive crystal run ./application.cr -Dpreview_mt
```

## Architecture

Sunflower has three layers:

```
┌─────────────────────────────────────┐
│           JavaScript (QuickJS)      │  Your application logic
├─────────────────────────────────────┤
│           Crystal Bridge            │  Bindings, async promises, IPC
├─────────────────────────────────────┤
│           GTK4 (Native)             │  Rendering, input, styling
└─────────────────────────────────────┘
```

The Crystal bridge connects GTK4 widgets to JavaScript objects. Every widget you declare in markup gets a corresponding JS object with methods and event handlers. Async operations (HTTP requests, file I/O) use a promise-based bridge — Crystal spawns a fiber, does the work, and resolves the JS promise when done.

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
| `Entry` | Text input field. Events: `change`. |
| `Image` | Displays images from local paths or URLs. |
| `ListBox` | Scrollable list container. |
| `ScrolledWindow` | Scrollable container for overflow content. |
| `Frame` | Visual grouping container with optional label. |
| `Tab` | Tabbed container. |
| `Switch` | Toggle switch. |
| `HorizontalSeparator` | Horizontal divider line. |
| `VerticalSeparator` | Vertical divider line. |

### Attributes

Every component supports:

- `id` — Unique identifier for JS access
- `className` — CSS class for styling
- `expand` — Whether the widget expands to fill available space

### Scripts

Embed JavaScript inline or load from a file:

```xml
<!-- Inline -->
<Script>
  console.log("Hello from Sunflower!");
</Script>

<!-- External -->
<Script src="scripts/index.js" />
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

$.getComponentById("myEntry").on.change = function(data) {
  console.log("Text changed: " + data);
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
label.setWrap(true);
label.setWrapMode("word");
label.setEllipsize("end");
label.setJustify("center");
label.setLines(3);
label.setMaxWidthChars(40);
label.setWidthChars(20);
label.setXAlign(0.5);
label.setYAlign(0.5);
label.setIsSelectable(true);
label.setIsSingleLineMode(false);
label.setUseMarkup(true);
label.setUseUnderline(true);
label.setNaturalWrapMode("word");
```

#### Entry

```javascript
var entry = $.getComponentById("myEntry");
entry.setText("Default value");
var text = entry.getText();
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

### Component State

Every component has a lazy `state` getter that reads the current widget state from GTK:

```javascript
var btn = $.getComponentById("myButton");
console.log(btn.state);  // { label: "Click Me", sensitive: true, ... }
```

### Lifecycle

```javascript
// Run code when the application is ready (all components mounted)
$.onReady(function() {
  console.log("I am ready!");
});

// Run code on exit
$.onExit = function() {
  console.log("Goodbye!");
};
```

### Async / Await

Sunflower has full async/await support. Any Crystal binding that does I/O returns a JS Promise that you can `await`:

```javascript
$.onReady(async function() {
  await img.setResourcePath("https://example.com/photo.jpg");
  console.log("Image loaded!");
});
```

## Built-in Modules

### `$.fs` — File System

```javascript
// Read a file
var content = await $.fs.read("/path/to/file.txt");

// Write a file
await $.fs.write("/path/to/file.txt", "Hello!");

// Append to a file
await $.fs.append("/path/to/log.txt", "New entry\n");

// Check if a file exists
var exists = await $.fs.exists("/path/to/file.txt");

// Delete a file
await $.fs.delete("/path/to/file.txt");

// Create directories (recursive)
await $.fs.mkdir("/path/to/new/dir");

// List directory contents
var entries = await $.fs.readdir("/path/to/dir");
console.log(entries); // ["file1.txt", "file2.txt", "subdir"]

// Get file information
var info = await $.fs.statistics("/path/to/file.txt");
console.log(info.size);        // bytes
console.log(info.isFile);      // true
console.log(info.isDirectory); // false
console.log(info.modifiedAt);  // unix timestamp

// Read/write binary data
await $.fs.writeBytes("/path/to/file.bin", new Uint8Array([0x89, 0x50, 0x4E, 0x47]));
var bytes = await $.fs.readBytes("/path/to/file.bin"); // Uint8Array
```

### `$.net` — Networking

```javascript
// GET request
var res = await $.net.get("https://api.example.com/data");
console.log(res.status);  // 200
console.log(res.body);    // response body string
console.log(res.headers); // { "content-type": "application/json", ... }

// GET with headers
var res = await $.net.get("https://api.example.com/data", {
  "Authorization": "Bearer token123"
});

// POST JSON
var res = await $.net.post("https://api.example.com/users", {
  name: "Giorgi",
  email: "giorgi@example.com"
}, {
  "Content-Type": "application/json"
});

// PUT, PATCH, DELETE
await $.net.put(url, body, headers);
await $.net.patch(url, body, headers);
await $.net.delete(url, headers);

// Generic request
var res = await $.net.request({
  url: "https://api.example.com/resource",
  method: "PATCH",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ updated: true })
});

// Download a file
var dl = await $.net.download("https://example.com/image.png", "/tmp/image.png");
console.log("Downloaded " + dl.bytes + " bytes to " + dl.path);
```

### Error Handling

All async module calls return an `error` field on failure instead of throwing:

```javascript
var res = await $.net.get("https://invalid.example.com");
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
console.warn("Warning message");   // prints to stderr with [WARN] prefix
console.error("Error message");    // prints to stderr with [ERROR] prefix

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
# The socket path is logged on startup
echo '{"id":"1","directory":".","file":"repl","line":1,"sourceCode":"console.log($.componentIds)"}' \
  | socat - UNIX-CONNECT:/tmp/<socket-id>.sock
```

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

## Contributing

1. Fork it (<https://github.com/grkek/sunflower/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Giorgi Kavrelishvili](https://github.com/grkek) - creator and maintainer
