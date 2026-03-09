/// Platform engine selector — conditional import hub.
///
/// Uses Dart's conditional imports to select the correct engine
/// factory for each platform:
/// - Web: WebEngine (dart:js_interop)
/// - Desktop: NodeEngine (dart:io + Process)
/// - iOS/macOS: JscEngine (dart:ffi + JavaScriptCore)
/// - Android: QuickJsEngine or NodeEngine (dart:ffi + QuickJS)
library;

export 'engine_selector_stub.dart'
    if (dart.library.js_interop) 'engine_selector_web.dart'
    if (dart.library.io) 'engine_selector_io.dart';
