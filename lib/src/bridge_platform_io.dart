/// IO (desktop/mobile) implementation of platform-specific bridge helpers.
library;

import 'dart:io';

import 'manifest.dart';

/// Load a manifest file, searching standard locations.
///
/// Returns `null` if no manifest is found or if disabled (empty path).
JsBridgerManifest? loadManifest(String? manifestPath) {
  // Disabled by empty string
  if (manifestPath == '') return null;

  // Explicit path
  if (manifestPath != null) {
    return JsBridgerManifest.load(manifestPath);
  }

  // Auto-detect: current dir, then parent dir
  final sep = Platform.pathSeparator;
  final cwd = Directory.current.path;
  final candidates = [
    '$cwd$sep${JsBridgerManifest.defaultFileName}',
    '${Directory.current.parent.path}$sep${JsBridgerManifest.defaultFileName}',
  ];
  for (final path in candidates) {
    final manifest = JsBridgerManifest.load(path);
    if (manifest != null) return manifest;
  }
  return null;
}

/// Resolve the working directory from config/manifest/default.
String resolveWorkingDir(String? configWorkDir, JsBridgerManifest? manifest) {
  if (configWorkDir != null) return configWorkDir;
  if (manifest != null) {
    return _resolveManifestWorkDir(manifest);
  }
  return '${Directory.current.path}${Platform.pathSeparator}.js_runtime';
}

/// Whether package management (npm) is available on this platform.
bool get isPackageManagementAvailable {
  // npm is available on desktop (Windows, macOS, Linux) but not on mobile
  return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}

String _resolveManifestWorkDir(JsBridgerManifest manifest) {
  final dir = manifest.workingDirectory;
  // Already absolute
  if (dir.startsWith('/') || dir.contains(':\\')) return dir;
  // Relative to manifest file
  final manifestDir = File(manifest.filePath).parent.path;
  return '$manifestDir${Platform.pathSeparator}$dir';
}
