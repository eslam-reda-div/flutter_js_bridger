/// Stub implementation — throws if platform is unsupported.
library;

import 'manifest.dart';

/// Stub — always throws.
JsBridgerManifest? loadManifest(String? manifestPath) =>
    throw UnsupportedError('Platform not supported');

/// Stub — always throws.
String resolveWorkingDir(String? configWorkDir, JsBridgerManifest? manifest) =>
    throw UnsupportedError('Platform not supported');

/// Stub — always false.
bool get isPackageManagementAvailable => false;
