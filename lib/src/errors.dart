/// Exception types for flutter_js_bridger.
///
/// Provides a typed error hierarchy for every failure scenario:
/// worker crashes, timeouts, JS runtime errors, module resolution, etc.
library;

/// Error codes covering all failure scenarios.
enum JsErrorCode {
  unknown,
  nodeNotFound,
  workerStartFailed,
  workerCrash,
  workerNotReady,
  timeout,
  protocolError,
  moduleNotFound,
  referenceNotFound,
  typeError,
  evalError,
  installFailed,
  removeFailed,
  packageNotFound,
}

/// Base exception for all flutter_js_bridger errors.
class JsBridgeException implements Exception {
  final JsErrorCode code;
  final String message;
  final String? jsStack;

  const JsBridgeException(this.code, this.message, {this.jsStack});

  /// Create from a worker error response map.
  factory JsBridgeException.fromWorker(Map<String, dynamic> error) {
    final message = error['message'] as String? ?? 'Unknown JS error';
    final stack = error['stack'] as String?;
    final code = error['code'] as String?;

    // Map known JS error types
    if (message.contains('Cannot find module') ||
        message.contains('MODULE_NOT_FOUND') ||
        code == 'MODULE_NOT_FOUND') {
      return JsModuleException(message, jsStack: stack);
    }
    if (message.contains('is not a function') ||
        message.contains('is not callable')) {
      return JsTypeException(message, jsStack: stack);
    }
    if (message.contains('Reference #') && message.contains('not found')) {
      return JsReferenceException(message, jsStack: stack);
    }

    return JsBridgeException(JsErrorCode.unknown, message, jsStack: stack);
  }

  @override
  String toString() {
    final buffer = StringBuffer('JsBridgeException[$code]: $message');
    if (jsStack != null) {
      buffer.writeln();
      buffer.write('  JS Stack: $jsStack');
    }
    return buffer.toString();
  }
}

/// Thrown when the Node.js runtime cannot be found or started.
class JsRuntimeException extends JsBridgeException {
  const JsRuntimeException(super.code, super.message, {super.jsStack});
}

/// Thrown when a request to the worker times out.
class JsTimeoutException extends JsBridgeException {
  const JsTimeoutException(String message)
      : super(JsErrorCode.timeout, message);
}

/// Thrown when a JS module cannot be found (require fails).
class JsModuleException extends JsBridgeException {
  const JsModuleException(String message, {String? jsStack})
      : super(JsErrorCode.moduleNotFound, message, jsStack: jsStack);
}

/// Thrown for JS TypeError (not a function, not a constructor, etc).
class JsTypeException extends JsBridgeException {
  const JsTypeException(String message, {String? jsStack})
      : super(JsErrorCode.typeError, message, jsStack: jsStack);
}

/// Thrown when a JS object reference is no longer valid.
class JsReferenceException extends JsBridgeException {
  const JsReferenceException(String message, {String? jsStack})
      : super(JsErrorCode.referenceNotFound, message, jsStack: jsStack);
}

/// Thrown when npm install/remove/update fails.
class JsPackageException extends JsBridgeException {
  final String? stderr;

  const JsPackageException(super.code, super.message, {this.stderr});

  @override
  String toString() {
    final buffer = StringBuffer('JsPackageException[$code]: $message');
    if (stderr != null && stderr!.isNotEmpty) {
      buffer.writeln();
      buffer.write('  npm stderr: $stderr');
    }
    return buffer.toString();
  }
}
