/// Platform abstraction for bridge.dart.
///
/// Provides platform-specific operations (manifest loading, working dir
/// resolution) via conditional imports so bridge.dart avoids dart:io.
library;

// Conditional import — selects the right implementation per platform.
export 'bridge_platform_stub.dart'
    if (dart.library.io) 'bridge_platform_io.dart'
    if (dart.library.js_interop) 'bridge_platform_web.dart';
