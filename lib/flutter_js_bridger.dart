/// Flutter JS Bridger — Use any npm package in your Flutter/Dart projects.
///
/// Provides a seamless bridge between Dart and the JavaScript ecosystem.
/// Install, load, and use any npm package directly from Dart with
/// natural, idiomatic syntax.
///
/// **Cross-platform**: Works on Desktop (Node.js), Web (dart:js_interop),
/// iOS/macOS (JavaScriptCore FFI), and Android (QuickJS FFI).
///
/// ## Quick Start (recommended — manifest-based)
///
/// ```bash
/// # Terminal — manage packages once:
/// dart run flutter_js_bridger init
/// dart run flutter_js_bridger add lodash
/// ```
///
/// ```dart
/// import 'package:flutter_js_bridger/flutter_js_bridger.dart';
///
/// void main() async {
///   final js = JsBridge();
///   await js.initialize();  // reads js_bridger.json, verifies deps
///
///   dynamic _ = await js.require('lodash');
///   var chunks = await _.chunk([1, 2, 3, 4, 5], 2);
///   print(chunks); // [[1, 2], [3, 4], [5]]
///
///   await js.dispose();
/// }
/// ```
library flutter_js_bridger;

export 'src/bridge.dart' show JsBridge, JsBridgeConfig;
export 'src/bundler.dart' show JsBundler;
export 'src/callback_manager.dart' show CallbackManager;
export 'src/engines/engine_interface.dart'
    show
        JsEngine,
        EngineConfig,
        EngineEvent,
        EngineCrashEvent,
        EngineRestartEvent,
        EngineReadyEvent;
export 'src/engines/in_process_engine.dart' show InProcessEngine;
export 'src/engines/node_engine.dart' show NodeEngine;
export 'src/errors.dart';
export 'src/js_object.dart' show JsObject, JsChain;
export 'src/manifest.dart' show JsBridgerManifest;
export 'src/package_manager.dart' show PackageManager;
