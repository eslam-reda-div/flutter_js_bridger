/// Web engine selector — always returns WebEngine.
library;

import 'engine_interface.dart';
import 'web_engine.dart';

/// Create the appropriate engine for web platforms.
JsEngine createPlatformEngine(EngineConfig config) {
  return WebEngine(config);
}
