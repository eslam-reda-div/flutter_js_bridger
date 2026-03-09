/// IO-platform engine selector — desktop and mobile.
///
/// Uses Platform detection to choose the best engine:
/// - iOS: JscEngine (system JavaScriptCore framework)
/// - macOS: NodeEngine on desktop (default), JscEngine if bundlePath is set
/// - Android: QuickJsEngine (bundled)
/// - Desktop (Windows/Linux): NodeEngine
library;

import 'dart:io';

import 'engine_interface.dart';
import 'jsc_engine.dart';
import 'node_engine.dart';
import 'quickjs_engine.dart';

/// Create the appropriate engine for the current IO platform.
JsEngine createPlatformEngine(EngineConfig config) {
  // iOS: Always use JavaScriptCore (system framework, no Node.js available)
  if (Platform.isIOS) {
    if (JscEngine.isAvailable) {
      return JscEngine(config);
    }
    throw UnsupportedError(
      'JavaScriptCore not available on this iOS device.',
    );
  }

  // macOS: Use NodeEngine by default (desktop), but if a bundlePath is
  // specified, the user wants embedded mode → use JSC.
  if (Platform.isMacOS) {
    if (config.bundlePath != null && JscEngine.isAvailable) {
      return JscEngine(config);
    }
    return NodeEngine(config);
  }

  // Android: Use QuickJS (no Node.js available)
  if (Platform.isAndroid) {
    if (QuickJsEngine.isAvailable) {
      return QuickJsEngine(config);
    }
    throw UnsupportedError(
      'No JavaScript engine available on Android. '
      'Include libquickjs.so in your app\'s native libraries. '
      'See flutter_js_bridger README for setup instructions.',
    );
  }

  // Desktop (Windows, Linux): Node.js subprocess
  return NodeEngine(config);
}
