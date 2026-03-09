/// Web implementation of platform-specific bridge helpers.
///
/// On web, no filesystem access — manifest loading is not supported,
/// and package management (npm) is not available.
library;

import 'manifest.dart';

/// Load a manifest file — not supported on web.
///
/// Always returns `null`. Web apps must configure bundlePath explicitly.
JsBridgerManifest? loadManifest(String? manifestPath) => null;

/// Resolve the working directory — returns a placeholder on web.
///
/// On web, the working directory is not used (no filesystem).
String resolveWorkingDir(String? configWorkDir, JsBridgerManifest? manifest) {
  return configWorkDir ?? '.js_runtime';
}

/// Package management is never available on web.
bool get isPackageManagementAvailable => false;
