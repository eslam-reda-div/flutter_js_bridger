/// Stub engine selector — used when neither dart:io nor dart:js_interop
/// is available. This should never happen in practice.
library;

import 'engine_interface.dart';

/// Create the appropriate engine for the current platform.
JsEngine createPlatformEngine(EngineConfig config) {
  throw UnsupportedError(
    'No JavaScript engine available for this platform. '
    'flutter_js_bridger requires dart:io (desktop/mobile) or '
    'dart:js_interop (web).',
  );
}
