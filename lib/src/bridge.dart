/// JsBridge — the main entry point for flutter_js_bridger.
///
/// Provides a high-level API for:
/// - Initializing the JS engine (auto-selects platform: Node.js, Web, mobile)
/// - Loading npm modules via `require()`
/// - Evaluating raw JavaScript
/// - Batch operations for efficient multi-call patterns
/// - Callback support (pass Dart functions to JS)
/// - Managing npm packages (install, remove, update, list)
/// - Reading `js_bridger.json` manifest for declarative dependency management
///
/// ## Recommended workflow (manifest-based):
///
/// ```bash
/// # Terminal — install packages once:
/// dart run flutter_js_bridger init
/// dart run flutter_js_bridger add lodash
/// ```
///
/// ```dart
/// // Code — just require, no install needed:
/// final js = JsBridge();
/// await js.initialize();
/// dynamic _ = await js.require('lodash');
/// var chunks = await _.chunk([1, 2, 3, 4, 5], 2);
/// await js.dispose();
/// ```
library;

import 'dart:async';

import 'bridge_platform.dart' as platform;
import 'callback_manager.dart';
import 'engines/engine_interface.dart';
import 'engines/engine_selector.dart';
import 'engines/in_process_engine.dart';
import 'engines/node_engine.dart';
import 'errors.dart';
import 'js_object.dart';
import 'manifest.dart';
import 'package_manager.dart';
import 'serializer.dart';

/// Configuration options for [JsBridge].
class JsBridgeConfig {
  /// Directory where node_modules and the worker script live.
  ///
  /// Defaults to the `working_directory` in `js_bridger.json`,
  /// or `.js_runtime/` if no manifest exists.
  final String? workingDirectory;

  /// Path to `js_bridger.json` manifest file.
  ///
  /// If `null`, automatically searches for the manifest in:
  /// 1. The current working directory
  /// 2. The parent directory (for packages inside /test, /bin, etc.)
  ///
  /// Set to empty string to disable manifest loading entirely.
  final String? manifestPath;

  /// Whether to auto-install missing packages from the manifest at runtime.
  ///
  /// - `false` (default): throws [JsPackageException] listing missing
  ///   packages and instructions to run the CLI installer.
  /// - `true`: silently installs missing packages on [JsBridge.initialize].
  ///   Useful for development but **not recommended for production**.
  final bool autoInstall;

  /// Timeout per IPC request in milliseconds (default: 60000).
  final int requestTimeout;

  /// Timeout for the worker to start in milliseconds (default: 30000).
  final int readyTimeout;

  /// Path to the Node.js binary (default: 'node').
  final String nodeBinary;

  /// Path to a pre-bundled JS file for web/mobile platforms.
  ///
  /// On web: URL to the bundle (e.g., 'assets/js_bundle.js')
  /// On mobile: filesystem path to the bundle
  ///
  /// Generate with: `dart run flutter_js_bridger bundle`
  final String? bundlePath;

  /// Maximum number of auto-restart attempts on engine crash.
  final int maxRestarts;

  /// Optional: provide your own engine instance.
  ///
  /// If set, the bridge skips platform detection and uses this engine.
  /// Useful for testing or custom engine implementations.
  final JsEngine? engine;

  const JsBridgeConfig({
    this.workingDirectory,
    this.manifestPath,
    this.autoInstall = false,
    this.requestTimeout = 60000,
    this.readyTimeout = 30000,
    this.nodeBinary = 'node',
    this.bundlePath,
    this.maxRestarts = 3,
    this.engine,
  });
}

/// Main entry point — bridges Dart to the JavaScript/npm ecosystem.
///
/// Create an instance, call [initialize], then use [require] to load
/// any npm package and interact with it through dynamic proxies.
///
/// **Cross-platform**: automatically selects the best JS engine:
/// - **Desktop** (Windows/macOS/Linux): Node.js subprocess
/// - **Web**: dart:js_interop (packages must be pre-bundled)
/// - **iOS/macOS mobile**: JavaScriptCore via FFI (system framework)
/// - **Android**: QuickJS via FFI (requires bundled native library)
///
/// ## With manifest (recommended):
/// ```dart
/// final js = JsBridge();
/// await js.initialize(); // reads js_bridger.json, verifies packages
/// dynamic _ = await js.require('lodash');
/// ```
///
/// ## Without manifest (legacy):
/// ```dart
/// final js = JsBridge(JsBridgeConfig(manifestPath: ''));
/// await js.initialize();
/// await js.install('lodash'); // installs at runtime
/// dynamic _ = await js.require('lodash');
/// ```
class JsBridge {
  final JsBridgeConfig _config;
  late final String _workingDir;
  late final JsEngine _engine;
  PackageManager? _packageManager;
  bool _initialized = false;
  JsBridgerManifest? _manifest;
  StreamSubscription<EngineEvent>? _eventSub;

  /// Callback manager for Dart→JS function passing.
  final CallbackManager callbacks = CallbackManager();

  /// Cache of already-required modules.
  final Map<String, JsObject> _moduleCache = {};

  JsBridge([JsBridgeConfig config = const JsBridgeConfig()]) : _config = config;

  /// Whether the bridge has been initialized.
  bool get isInitialized => _initialized;

  /// The loaded manifest, or `null` if none was found/configured.
  JsBridgerManifest? get manifest => _manifest;

  /// The underlying engine (available after [initialize]).
  JsEngine get engine => _engine;

  /// Stream of engine lifecycle events (crashes, restarts, ready).
  ///
  /// Safe to listen to before [initialize] — returns an empty stream
  /// until the engine is created.
  Stream<EngineEvent> get events =>
      _initialized ? _engine.events : const Stream.empty();

  // ═══════════════════════════════════════════════════════
  //  Lifecycle
  // ═══════════════════════════════════════════════════════

  /// Initialize the bridge: load manifest, start the engine, verify packages.
  ///
  /// 1. Loads `js_bridger.json` manifest (if available)
  /// 2. Determines the working directory
  /// 3. Creates and starts the appropriate platform engine
  /// 4. Verifies all manifest dependencies are installed
  ///
  /// If packages are missing and [JsBridgeConfig.autoInstall] is `false`,
  /// throws [JsPackageException] with instructions to run the CLI.
  Future<void> initialize() async {
    if (_initialized) return;

    // 1. Load manifest (platform-specific: IO reads file, web returns null)
    _manifest = platform.loadManifest(_config.manifestPath);

    // 2. Determine working directory (config > manifest > default)
    _workingDir =
        platform.resolveWorkingDir(_config.workingDirectory, _manifest);

    // 3. Create engine (user-provided or auto-detected)
    if (_config.engine != null) {
      _engine = _config.engine!;
    } else {
      final engineConfig = EngineConfig(
        workingDirectory: _workingDir,
        requestTimeout: _config.requestTimeout,
        readyTimeout: _config.readyTimeout,
        nodeBinary: _config.nodeBinary,
        bundlePath: _config.bundlePath,
        maxRestarts: _config.maxRestarts,
      );
      _engine = createPlatformEngine(engineConfig);
    }

    // Only create PackageManager on platforms that support it
    if (platform.isPackageManagementAvailable) {
      _packageManager = PackageManager(_workingDir);
    }

    // Listen for engine events (for auto-reconnect module reload)
    _eventSub = _engine.events.listen(_onEngineEvent);

    // Set up callback handler for all engine types
    if (_engine is NodeEngine) {
      (_engine as NodeEngine).onCallback = _handleCallback;
    } else if (_engine is InProcessEngine) {
      (_engine as InProcessEngine).onCallback = _handleCallbackSync;
    }

    await _engine.start();
    _initialized = true;

    // 4. Verify manifest dependencies (only on desktop with npm)
    if (platform.isPackageManagementAvailable &&
        _engine is NodeEngine &&
        _manifest != null &&
        _manifest!.dependencies.isNotEmpty) {
      final missing =
          _packageManager!.findMissingPackages(_manifest!.dependencies);
      if (missing.isNotEmpty) {
        if (_config.autoInstall) {
          final toInstall = missing.map((pkg) {
            final version = _manifest!.dependencies[pkg]!;
            if (version == '*' || version == 'latest' || version.isEmpty) {
              return pkg;
            }
            return '$pkg@$version';
          }).toList();
          await _packageManager!.install(toInstall);
        } else {
          throw JsPackageException(
            JsErrorCode.packageNotFound,
            'Missing npm packages: ${missing.join(", ")}\n'
            'Run: dart run flutter_js_bridger install',
          );
        }
      }
    }
  }

  /// Shut down the engine and release all resources.
  Future<void> dispose() async {
    if (!_initialized) return;
    _moduleCache.clear();
    callbacks.clear();
    await _eventSub?.cancel();
    await _engine.shutdown();
    _initialized = false;
  }

  // ═══════════════════════════════════════════════════════
  //  Module Loading
  // ═══════════════════════════════════════════════════════

  /// Load an npm module by name.
  ///
  /// Returns a dynamic proxy ([JsObject]) that intercepts all
  /// property access and method calls, forwarding them to JS.
  ///
  /// ```dart
  /// dynamic lodash = await js.require('lodash');
  /// var result = await lodash.chunk([1, 2, 3, 4], 2);
  /// ```
  Future<dynamic> require(String module) async {
    _ensureInitialized();

    // Check cache
    if (_moduleCache.containsKey(module)) {
      return _moduleCache[module]!;
    }

    final result = await _engine.send({
      'action': 'require',
      'module': module,
    });

    final wrapped = wrapResult(_engine, result, callbacks: callbacks);
    if (wrapped is JsObject) {
      _moduleCache[module] = wrapped;
    }
    return wrapped;
  }

  /// Evaluate raw JavaScript code and return the result.
  ///
  /// ```dart
  /// var sum = await js.eval('2 + 2'); // 4
  /// var arr = await js.eval('[1, 2, 3].map(x => x * 2)'); // [2, 4, 6]
  /// ```
  Future<dynamic> eval(String code) async {
    _ensureInitialized();
    final result = await _engine.send({
      'action': 'eval',
      'code': code,
    });
    return wrapResult(_engine, result, callbacks: callbacks);
  }

  /// Access a JavaScript global variable by name.
  ///
  /// Returns a [JsObject] proxy for the global, or a primitive.
  /// Use this instead of `eval` to access globals like `process`,
  /// `String`, `Number`, `Date`, `RegExp`, `JSON`, etc.
  ///
  /// ```dart
  /// dynamic process = await js.getGlobal('process');
  /// var env = await process.env;
  ///
  /// dynamic JsString = await js.getGlobal('String');
  /// dynamic JsNumber = await js.getGlobal('Number');
  /// ```
  Future<dynamic> getGlobal(String name) async {
    _ensureInitialized();
    final result = await _engine.send({
      'action': 'get_global',
      'name': name,
    });
    return wrapResult(_engine, result, callbacks: callbacks);
  }

  /// Set a value on `globalThis`.
  ///
  /// ```dart
  /// await js.setGlobal('__myFlag', true);
  /// await js.setGlobal('__server', null);
  /// ```
  Future<void> setGlobal(String name, dynamic value) async {
    _ensureInitialized();
    await _engine.send({
      'action': 'set_global',
      'name': name,
      'value': serializeArg(value, callbacks: callbacks),
    });
  }

  /// Create a JavaScript function from parameter names and a body string.
  ///
  /// Uses `new Function()` under the hood — sandboxed scope (no access to
  /// worker internals). Returns a [JsObject] reference to the function.
  ///
  /// ```dart
  /// final double = await js.createFunction(
  ///   params: ['x'],
  ///   body: 'return x * 2',
  /// );
  /// final result = await R.map(double, [1, 2, 3]); // [2, 4, 6]
  /// ```
  Future<dynamic> createFunction({
    required String body,
    List<String> params = const [],
  }) async {
    _ensureInitialized();
    final result = await _engine.send({
      'action': 'create_function',
      'params': params,
      'body': body,
    });
    return wrapResult(_engine, result, callbacks: callbacks);
  }

  /// Ping the engine to check if it's alive.
  Future<bool> ping() async {
    _ensureInitialized();
    try {
      final result = await _engine.send({'action': 'ping'});
      return result == 'pong';
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  //  Batch Operations
  // ═══════════════════════════════════════════════════════

  /// Execute multiple operations in a single round-trip.
  ///
  /// Much more efficient than sequential calls when you need
  /// to perform several independent JS operations.
  ///
  /// ```dart
  /// final results = await js.batch([
  ///   {'action': 'eval', 'code': '1 + 1'},
  ///   {'action': 'eval', 'code': '2 + 2'},
  ///   {'action': 'eval', 'code': '3 + 3'},
  /// ]);
  /// // results: [2, 4, 6]
  /// ```
  Future<List<dynamic>> batch(List<Map<String, dynamic>> requests) async {
    _ensureInitialized();
    final results = await _engine.sendBatch(requests);
    return results
        .map((r) => wrapResult(_engine, r, callbacks: callbacks))
        .toList();
  }

  // ═══════════════════════════════════════════════════════
  //  Package Management (runtime)
  // ═══════════════════════════════════════════════════════

  /// Install an npm package at runtime.
  ///
  /// **Desktop only** — throws [UnsupportedError] on web/mobile.
  ///
  /// **Prefer using the CLI** for production apps:
  /// ```bash
  /// dart run flutter_js_bridger add lodash
  /// ```
  Future<void> install(String package) => installAll([package]);

  /// Install multiple npm packages at runtime.
  ///
  /// **Desktop only** — throws [UnsupportedError] on web/mobile.
  Future<void> installAll(List<String> packages) async {
    _ensureInitialized();
    _ensurePackageManagement();
    await _packageManager!.install(packages);
  }

  /// Remove an npm package.
  ///
  /// **Desktop only** — throws [UnsupportedError] on web/mobile.
  Future<void> remove(String package) => removeAll([package]);

  /// Remove multiple npm packages at once.
  ///
  /// **Desktop only** — throws [UnsupportedError] on web/mobile.
  Future<void> removeAll(List<String> packages) async {
    _ensureInitialized();
    _ensurePackageManagement();
    for (final pkg in packages) {
      _moduleCache.remove(pkg);
    }
    await _packageManager!.remove(packages);
  }

  /// Update npm packages. If none specified, updates all.
  ///
  /// **Desktop only** — throws [UnsupportedError] on web/mobile.
  Future<void> update([List<String> packages = const []]) async {
    _ensureInitialized();
    _ensurePackageManagement();
    await _packageManager!.update(packages);
  }

  /// List installed npm packages with versions.
  ///
  /// **Desktop only** — throws [UnsupportedError] on web/mobile.
  Future<Map<String, String>> listPackages() async {
    _ensureInitialized();
    _ensurePackageManagement();
    return _packageManager!.list();
  }

  /// Check if a package is installed.
  ///
  /// **Desktop only** — throws [UnsupportedError] on web/mobile.
  Future<bool> isInstalled(String package) async {
    _ensureInitialized();
    _ensurePackageManagement();
    return _packageManager!.isInstalled(package);
  }

  /// Register a Dart callback that can be invoked from JavaScript.
  ///
  /// Returns the callback ID that JS uses to invoke it.
  int registerCallback(Function callback) {
    return callbacks.register(callback);
  }

  /// Register a one-shot Dart callback — auto-unregisters after first call.
  ///
  /// Useful for Promise `.then()`, event listeners that fire once, etc.
  int registerOneShotCallback(Function callback) {
    return callbacks.registerOneShot(callback);
  }

  /// Unregister a previously registered callback.
  void unregisterCallback(int callbackId) {
    callbacks.unregister(callbackId);
  }

  // ─── Private ───────────────────────────────────────

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'JsBridge not initialized. Call initialize() first.',
      );
    }
  }

  void _ensurePackageManagement() {
    if (!platform.isPackageManagementAvailable) {
      throw UnsupportedError(
        'Package management (npm) is only available on desktop platforms. '
        'On mobile/web, use the CLI to bundle packages: '
        'dart run flutter_js_bridger bundle',
      );
    }
  }

  /// Handle JS→Dart callback invocations (Node.js engine — with invokeId).
  void _handleCallback(int callbackId, List<dynamic> args, int? invokeId) {
    final wrappedArgs =
        args.map((a) => wrapResult(_engine, a, callbacks: callbacks)).toList();
    try {
      final result = callbacks.invoke(callbackId, wrappedArgs);
      if (result is Future) {
        result.then((value) {
          if (_engine is NodeEngine) {
            (_engine as NodeEngine).sendCallbackResponse(
              callbackId,
              invokeId: invokeId,
              result: serializeArg(value, callbacks: callbacks),
            );
          }
        }).catchError((e) {
          if (_engine is NodeEngine) {
            (_engine as NodeEngine).sendCallbackResponse(
              callbackId,
              invokeId: invokeId,
              error: e.toString(),
            );
          }
        });
      } else {
        if (_engine is NodeEngine) {
          (_engine as NodeEngine).sendCallbackResponse(
            callbackId,
            invokeId: invokeId,
            result: serializeArg(result, callbacks: callbacks),
          );
        }
      }
    } catch (e) {
      if (_engine is NodeEngine) {
        (_engine as NodeEngine).sendCallbackResponse(
          callbackId,
          invokeId: invokeId,
          error: e.toString(),
        );
      }
    }
  }

  /// Handle JS→Dart callbacks for in-process engines (fire-and-forget, no invokeId).
  void _handleCallbackSync(int callbackId, List<dynamic> args) {
    final wrappedArgs =
        args.map((a) => wrapResult(_engine, a, callbacks: callbacks)).toList();
    try {
      callbacks.invoke(callbackId, wrappedArgs);
    } catch (_) {
      // In-process callbacks are fire-and-forget
    }
  }

  /// Handle engine lifecycle events.
  void _onEngineEvent(EngineEvent event) {
    if (event is EngineReadyEvent && _moduleCache.isNotEmpty) {
      _reloadModules();
    }
  }

  /// Re-require all cached modules after engine restart.
  Future<void> _reloadModules() async {
    final moduleNames = List<String>.from(_moduleCache.keys);
    _moduleCache.clear();
    for (final name in moduleNames) {
      try {
        await require(name);
      } catch (_) {
        // Module may not be available after restart
      }
    }
  }
}
