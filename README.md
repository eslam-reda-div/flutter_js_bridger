# Flutter JS Bridger

**Use any npm package in your Flutter & Dart projects — on every platform.**

Flutter JS Bridger creates a seamless bridge between Dart and the JavaScript ecosystem. It works on **desktop** (Node.js subprocess), **web** (dart:js_interop), **iOS/macOS** (JavaScriptCore FFI), and **Android** (QuickJS FFI). Declare npm dependencies in a manifest, install them via CLI, bundle for mobile/web, then use them from Dart with natural syntax.

```dart
final js = JsBridge();
await js.initialize();

dynamic _ = await js.require('lodash');
var chunks = await _.chunk([1, 2, 3, 4, 5], 2);
// [[1, 2], [3, 4], [5]]
```

## Features

- **Any npm package** — lodash, axios, moment, uuid, validator, you name it
- **Cross-platform** — Desktop, Web, iOS, macOS, Android, Linux
- **Pluggable engine architecture** — auto-selects the right JS engine per platform
- **Declarative dependency management** — `js_bridger.json` manifest with CLI tools
- **JS bundler** — bundle npm packages into a single file for mobile & web
- **Batch API** — send multiple operations in one round-trip
- **Callback support** — pass Dart functions to JavaScript
- **Auto-reconnect** — engine restarts automatically on crash (desktop)
- **Batch GC** — reference cleanup is batched for performance
- **Natural Dart syntax** — method calls, property access, chaining
- **Path chaining** — `await obj.nested.deep.method(args)` in a single call
- **Automatic memory management** — JS references cleaned up by Dart's GC
- **Async/Promise support** — JS Promises are automatically awaited
- **Raw JS eval** — evaluate any JavaScript expression
- **Type-safe errors** — typed Dart exceptions for every failure scenario

## Platform Support

| Platform    | Engine        | How it works                        | Setup required             |
| ----------- | ------------- | ----------------------------------- | -------------------------- |
| **Windows** | NodeEngine    | Node.js subprocess + JSON IPC       | Node.js in PATH            |
| **macOS**   | JscEngine     | JavaScriptCore via FFI (system lib) | None (system framework)    |
| **Linux**   | NodeEngine    | Node.js subprocess + JSON IPC       | Node.js in PATH            |
| **iOS**     | JscEngine     | JavaScriptCore via FFI (system lib) | None (system framework)    |
| **Android** | QuickJsEngine | QuickJS via FFI                     | `libquickjs.so` in jniLibs |
| **Web**     | WebEngine     | dart:js_interop + eval              | None                       |

The engine is **auto-selected** at runtime — no configuration needed for most cases.

## Prerequisites

| Requirement  | Version  | Needed for      |
| ------------ | -------- | --------------- |
| **Dart SDK** | ≥ 3.0.0  | All platforms   |
| **Node.js**  | ≥ 16.0.0 | Desktop + CLI   |
| **npm**      | ≥ 8.0.0  | Package install |

Node.js is only required for desktop platforms and CLI operations (install, bundle). Mobile and web platforms use embedded JS engines.

## Installation

```yaml
dependencies:
  flutter_js_bridger: ^2.0.0
```

```bash
dart pub add flutter_js_bridger
```

## Quick Start

### Desktop (Windows / macOS / Linux)

```bash
# 1. Initialize manifest
dart run flutter_js_bridger init

# 2. Add packages
dart run flutter_js_bridger add lodash axios

# 3. Use in Dart
```

```dart
import 'package:flutter_js_bridger/flutter_js_bridger.dart';

void main() async {
  final js = JsBridge();
  await js.initialize();

  dynamic _ = await js.require('lodash');
  var chunks = await _.chunk([1, 2, 3, 4, 5, 6], 2);
  print(chunks); // [[1, 2], [3, 4], [5, 6]]

  await js.dispose();
}
```

### Mobile & Web (iOS / Android / Web)

Mobile and web platforms can't run Node.js, so you **bundle** your npm packages into a single JS file:

```bash
# 1. Add packages normally
dart run flutter_js_bridger add lodash moment

# 2. Bundle for mobile/web
dart run flutter_js_bridger bundle --output assets/bundle.js
```

```dart
final js = JsBridge(JsBridgeConfig(
  bundlePath: 'assets/bundle.js',
));
await js.initialize();

dynamic _ = await js.require('lodash');
var result = await _.camelCase('hello world');
```

The bundler uses **esbuild** (if available) or falls back to basic concatenation. The bundle file registers all modules so `require()` works inside the embedded engine.

### Callbacks (Dart → JS → Dart)

Pass Dart functions to JavaScript:

```dart
final js = JsBridge();
await js.initialize();

// Register a callback
js.registerCallback('myHandler', (List args) {
  print('Called from JS with: $args');
  return args[0] * 2;
});

// Use in JS
var result = await js.eval('''
  const handler = createDartCallback(1);
  handler(21);
''');
print(result); // 42
```

### Batch Operations

Send multiple operations in a single round-trip:

```dart
final results = await js.batch([
  {'action': 'call', 'refId': ref, 'method': 'add', 'args': [1, 2]},
  {'action': 'call', 'refId': ref, 'method': 'multiply', 'args': [3, 4]},
  {'action': 'eval', 'code': '1 + 1'},
]);
// results = [3, 12, 2]
```

## CLI Reference

```bash
dart run flutter_js_bridger <command> [arguments]
```

| Command               | Description                                         |
| --------------------- | --------------------------------------------------- |
| `init`                | Create a new `js_bridger.json` manifest             |
| `add <pkg>[@version]` | Add a package to the manifest and install it        |
| `remove <pkg>`        | Remove a package from the manifest and uninstall it |
| `install`             | Install all packages declared in the manifest       |
| `update [pkg]`        | Update packages (all if none specified)             |
| `list`                | Show declared vs installed packages with versions   |
| `check`               | Verify all manifest packages are installed          |
| `bundle [-o path]`    | Bundle all manifest packages into a single JS file  |

### Examples

```bash
# Initialize
dart run flutter_js_bridger init

# Add packages
dart run flutter_js_bridger add lodash
dart run flutter_js_bridger add axios@^1.6.0
dart run flutter_js_bridger add moment uuid validator

# Bundle for mobile/web
dart run flutter_js_bridger bundle --output assets/js_bundle.js

# Verify everything is installed
dart run flutter_js_bridger check

# List packages with status
dart run flutter_js_bridger list

# Remove a package
dart run flutter_js_bridger remove moment

# Reinstall everything (e.g., after cloning)
dart run flutter_js_bridger install
```

### Manifest Format (`js_bridger.json`)

```json
{
  "version": "1.0.0",
  "node": ">=16.0.0",
  "working_directory": ".js_runtime",
  "dependencies": {
    "axios": "^1.6.0",
    "lodash": "^4.17.23"
  }
}
```

| Field               | Description                                                            |
| ------------------- | ---------------------------------------------------------------------- |
| `version`           | Manifest schema version                                                |
| `node`              | Required Node.js version constraint                                    |
| `working_directory` | Where `node_modules` and the worker script live (relative to manifest) |
| `dependencies`      | npm packages with semver version constraints                           |

> **Tip:** Add `js_bridger.json` to version control and `.js_runtime/` to `.gitignore`.

## API Reference

### JsBridge

#### Configuration

```dart
final js = JsBridge(JsBridgeConfig(
  workingDirectory: '/path/to/js/workspace',  // optional
  manifestPath: 'js_bridger.json',            // optional, auto-detected
  autoInstall: false,                         // auto-install missing deps?
  requestTimeout: 60000,                      // ms, default: 60s
  readyTimeout: 30000,                        // ms, default: 30s
  nodeBinary: 'node',                         // default: 'node'
  bundlePath: 'assets/bundle.js',             // for mobile/web
  maxRestarts: 3,                             // auto-restart limit (desktop)
  engine: myCustomEngine,                     // override auto-detection
));

await js.initialize();
await js.dispose();
```

#### Engine Events

Listen to engine lifecycle events (desktop with auto-reconnect):

```dart
js.events.listen((event) {
  switch (event) {
    case EngineCrashEvent(:final exitCode, :final error):
      print('Engine crashed: $error (exit: $exitCode)');
    case EngineRestartEvent(:final attempt):
      print('Restarting... attempt $attempt');
    case EngineReadyEvent():
      print('Engine ready');
  }
});
```

#### Module Loading

```dart
dynamic lodash = await js.require('lodash');
dynamic path = await js.require('path');
dynamic axios = await js.require('axios');

var result = await js.eval('2 + 2');
var arr = await js.eval('[1,2,3].map(x => x * 2)');
```

#### Package Management (runtime, desktop only)

```dart
await js.install('lodash');
await js.remove('moment');
await js.update(['lodash']);
await js.update();

var packages = await js.listPackages();
var installed = await js.isInstalled('lodash');
```

### Dynamic Proxy (JsObject)

```dart
dynamic _ = await js.require('lodash');

// Method calls
var result = await _.chunk([1, 2, 3, 4], 2);
var merged = await _.merge({'a': 1}, {'b': 2});

// Property access
dynamic path = await js.require('path');
var sep = await path.sep;

// Chained access (single call for the chain!)
dynamic obj = await js.eval('({a: {b: {c: 42}}})');
var value = await obj.a.b.c;  // 42

// Call as function
dynamic fn = await js.eval('((x) => x * 2)');
var doubled = await fn(21);  // 42

// Construct instances
dynamic DateClass = await js.eval('Date');
dynamic d = await (DateClass as JsObject).$new(['2026-01-01']);
var year = await d.getFullYear();  // 2026
```

### Explicit API ($-prefixed methods)

```dart
JsObject obj = await js.require('lodash') as JsObject;

await obj.$get('VERSION');
await obj.$set('customProp', 42);
await obj.$call('chunk', [[1,2,3,4], 2]);

var keys = await obj.$keys();
var type = await obj.$typeof();
var has = await obj.$has('chunk');

await obj.dispose();
```

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                    JsBridge (Dart)                     │
│  ┌────────────┐  ┌──────────────┐  ┌───────────────┐ │
│  │ JsObject    │  │ CallbackMgr  │  │ PackageManager│ │
│  │ JsChain     │  │ (Dart↔JS)    │  │ (npm CLI)     │ │
│  └─────┬──────┘  └──────┬───────┘  └───────────────┘ │
│        │                │                             │
│  ┌─────▼────────────────▼──────────────────────────┐  │
│  │           JsEngine (abstract interface)          │  │
│  └──────────┬──────────┬──────────┬────────────────┘  │
└─────────────┼──────────┼──────────┼──────────────────┘
              │          │          │
    ┌─────────▼──┐ ┌─────▼────┐ ┌──▼──────────┐
    │ NodeEngine  │ │WebEngine │ │InProcessEngine│
    │ (Desktop)   │ │ (Web)    │ │ (base class) │
    │             │ │          │ │  ┌──────────┐│
    │ Node.js     │ │ eval()   │ │  │JscEngine ││
    │ subprocess  │ │ dart:    │ │  │(iOS/macOS)││
    │ JSON IPC    │ │ js_interop│ │  ├──────────┤│
    │             │ │          │ │  │QuickJs   ││
    │ Batch GC    │ │          │ │  │(Android) ││
    │ Auto-restart│ │          │ │  └──────────┘│
    └─────────────┘ └──────────┘ └──────────────┘
```

1. **CLI** manages `js_bridger.json` and installs packages at development time
2. **`bundle` command** creates a single JS file from npm packages for mobile/web
3. **JsBridge.initialize()** auto-selects the right engine for the current platform
4. **Desktop**: spawns Node.js worker, communicates via JSON over stdin/stdout
5. **Web**: loads JS via `eval()` using dart:js_interop
6. **iOS/macOS**: calls JavaScriptCore framework directly via dart:ffi (zero extra deps)
7. **Android**: calls QuickJS via dart:ffi (requires compiled `libquickjs.so`)
8. JS objects are tracked by reference IDs — Dart gets lightweight proxy objects
9. Batch GC coalesces reference cleanup for better performance

## Android Setup (QuickJS)

To use on Android, include a compiled QuickJS shared library:

1. Compile QuickJS with the bridger shim (see [jsc_engine.dart](lib/src/engines/jsc_engine.dart) docs)
2. Place `libquickjs.so` for each ABI in:
   ```
   android/src/main/jniLibs/
   ├── arm64-v8a/libquickjs.so
   ├── armeabi-v7a/libquickjs.so
   └── x86_64/libquickjs.so
   ```
3. Bundle your npm packages: `dart run flutter_js_bridger bundle -o assets/bundle.js`
4. The engine loads automatically on Android.

## Error Handling

```dart
try {
  await js.require('nonexistent-package');
} on JsModuleException catch (e) {
  print('Module not found: ${e.message}');
} on JsPackageException catch (e) {
  print('Package error: ${e.message}');
} on JsTimeoutException catch (e) {
  print('Timed out: ${e.message}');
} on JsTypeException catch (e) {
  print('Type error: ${e.message}');
} on JsBridgeException catch (e) {
  print('Bridge error [${e.code}]: ${e.message}');
}
```

## Project Setup Checklist

1. `dart pub add flutter_js_bridger` — add the package
2. `dart run flutter_js_bridger init` — create the manifest
3. `dart run flutter_js_bridger add <packages>` — add your npm dependencies
4. `dart run flutter_js_bridger bundle -o assets/bundle.js` — bundle for mobile/web
5. Add `.js_runtime/` to your `.gitignore`
6. Commit `js_bridger.json` to version control
7. After cloning: `dart run flutter_js_bridger install` to restore packages

## License

MIT — see [LICENSE](LICENSE) for details.
