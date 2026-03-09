// ignore_for_file: avoid_print
import 'package:flutter_js_bridger/flutter_js_bridger.dart';

/// ═══════════════════════════════════════════════════════════════
///  flutter_js_bridger — Quick Start Example
/// ═══════════════════════════════════════════════════════════════
///
/// A quick overview of the bridge's core features. For detailed
/// examples of specific packages, see the other files in this folder:
///
///   express_crud_api.dart   — Full REST API with Express.js
///   websocket_chat.dart     — Real-time WebSocket chat server
///   jwt_auth.dart           — JWT authentication + bcrypt passwords
///   sqlite_database.dart    — SQLite CRUD with better-sqlite3
///   data_processing.dart    — Data manipulation with lodash + ramda
///   date_utils.dart         — Date handling with Day.js + Moment.js
///   schema_validation.dart  — Input validation with Zod + Joi
///
/// Setup:
///   dart run flutter_js_bridger init
///   dart run flutter_js_bridger add lodash dayjs
///
/// Run:
///   dart run example/bin/example.dart
void main() async {
  final js = JsBridge();

  try {
    // ──────────────────────────────────────
    //  1. Initialize the bridge
    // ──────────────────────────────────────
    print('Initializing JS Bridge...');
    await js.initialize();
    print('Bridge ready!\n');

    // ──────────────────────────────────────
    //  2. Use lodash via require()
    // ──────────────────────────────────────
    print('=== lodash ===');
    final dynamic lo = await js.require('lodash');

    final chunks = await lo.chunk([1, 2, 3, 4, 5, 6], 2);
    print('lo.chunk([1,2,3,4,5,6], 2) = $chunks');

    final flat = await lo.flatten([
      [1, 2],
      [3, 4],
      [5]
    ]);
    print('lo.flatten([[1,2],[3,4],[5]]) = $flat');

    final unique = await lo.uniq([1, 2, 2, 3, 3, 3]);
    print('lo.uniq([1,2,2,3,3,3]) = $unique');

    final camel = await lo.camelCase('hello world foo bar');
    print('lo.camelCase("hello world foo bar") = $camel');

    // ──────────────────────────────────────
    //  3. Direct JS evaluation
    // ──────────────────────────────────────
    print('\n=== eval ===');
    final sum = await js.eval('2 + 2');
    print('eval("2 + 2") = $sum');

    final arr = await js.eval('[1, 2, 3].map(x => x * 10)');
    print('eval("[1,2,3].map(x => x * 10)") = $arr');

    final now = await js.eval('new Date().toISOString()');
    print('eval("new Date().toISOString()") = $now');

    // ──────────────────────────────────────
    //  4. Batch operations (single round-trip)
    // ──────────────────────────────────────
    print('\n=== batch ===');
    final results = await js.batch([
      {'action': 'eval', 'code': '1 + 1'},
      {'action': 'eval', 'code': '"hello".toUpperCase()'},
      {'action': 'eval', 'code': 'Math.PI.toFixed(4)'},
    ]);
    print('batch results: $results');

    // ──────────────────────────────────────
    //  5. Dart→JS callbacks
    // ──────────────────────────────────────
    print('\n=== callbacks ===');
    final cbId = js.registerCallback((List<dynamic> args) {
      print('  Dart callback invoked with: $args');
      return (args[0] as num) * 2;
    });
    print('Registered callback id: $cbId');

    // ──────────────────────────────────────
    //  6. List installed packages (desktop)
    // ──────────────────────────────────────
    print('\n=== installed packages ===');
    final packages = await js.listPackages();
    for (final entry in packages.entries) {
      print('  ${entry.key}: ${entry.value}');
    }

    // ──────────────────────────────────────
    //  7. Health check
    // ──────────────────────────────────────
    print('\n=== ping ===');
    final alive = await js.ping();
    print('Engine alive: $alive');

    print('\nDone!');
  } catch (e) {
    print('Error: $e');
  } finally {
    await js.dispose();
  }
}
