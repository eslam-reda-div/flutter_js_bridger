import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

import '../helpers/npm_test_helper.dart';

/// Tests for ws (WebSocket) — real-time communication from Dart.
///
/// Uses Dart-native proxy API — zero eval. JS WebSocketServer with
/// createFunction for event handlers; Dart WebSocket for client connections.
void main() {
  late JsBridge js;
  dynamic wsServer;
  int? wsPort;

  setUpAll(() async {
    js = await createNpmTestBridge();
    await ensureInstalled(js, 'ws');
  });

  tearDownAll(() async {
    try {
      if (wsServer != null) await wsServer.close();
    } catch (_) {}
    await js.dispose();
  });

  group('ws — WebSocket', () {
    test('require ws', () async {
      final dynamic ws = await js.require('ws');
      expect(ws, isNotNull);
      expect(ws, isA<JsObject>());

      // Check that ws module has WebSocketServer
      expect(await ws.$has('WebSocketServer'), isTrue);
    });

    test('create WebSocket server', () async {
      final dynamic wsMod = await js.require('ws');
      dynamic WSS = await wsMod.WebSocketServer;
      dynamic wss = await WSS.$new([
        {'port': 0}
      ]);
      // Wait for server to be bound (IPC round-trips give event loop time)
      for (var i = 0; i < 100; i++) {
        final a = await wss.address();
        if (a != null) break;
      }
      dynamic addr = await wss.address();
      wsPort = (await addr.port) as int;
      wsServer = wss;
      expect(wsPort, greaterThan(0));
    });

    test('WebSocket server accepts connections and echoes', () async {
      // Set up echo handler on the server via createFunction
      final connHandler = await js.createFunction(
        params: ['ws'],
        body:
            "ws.on('message', function(msg) { ws.send('echo: ' + msg.toString()); }); "
            "ws.send('welcome');",
      );
      await wsServer.on('connection', connHandler);

      // Connect using Dart's WebSocket
      final ws = await WebSocket.connect('ws://localhost:$wsPort');
      final messages = <String>[];
      final completer = Completer<void>();

      ws.listen((data) {
        messages.add(data.toString());
        if (messages.length == 1) {
          ws.add('hello from Dart');
        } else if (messages.length >= 2) {
          if (!completer.isCompleted) completer.complete();
        }
      });

      await completer.future.timeout(const Duration(seconds: 5));
      await ws.close();

      expect(messages.length, equals(2));
      expect(messages[0], equals('welcome'));
      expect(messages[1], equals('echo: hello from Dart'));
    });

    test('WebSocket server — multiple clients', () async {
      Future<List<String>> connectClient(int port) async {
        final ws = await WebSocket.connect('ws://localhost:$port');
        final msgs = <String>[];
        final completer = Completer<void>();
        ws.listen((data) {
          msgs.add(data.toString());
          if (msgs.length >= 2 && !completer.isCompleted) {
            completer.complete();
          }
        });
        ws.add('ping');
        await completer.future.timeout(const Duration(seconds: 3));
        await ws.close();
        return msgs;
      }

      final results = await Future.wait([
        connectClient(wsPort!),
        connectClient(wsPort!),
      ]);
      expect(results[0].length, greaterThanOrEqualTo(2));
      expect(results[1].length, greaterThanOrEqualTo(2));
    });

    test('WebSocket — JSON data exchange', () async {
      final dynamic wsMod = await js.require('ws');
      dynamic WSS = await wsMod.WebSocketServer;
      dynamic jsonServer = await WSS.$new([
        {'port': 0}
      ]);
      for (var i = 0; i < 100; i++) {
        final a = await jsonServer.address();
        if (a != null) break;
      }
      dynamic addr = await jsonServer.address();
      final jPort = await addr.port;

      final jsonHandler = await js.createFunction(
        params: ['ws'],
        body: "ws.on('message', function(raw) { "
            "var data = JSON.parse(raw.toString()); "
            "ws.send(JSON.stringify({ type: 'response', result: data.a + data.b, original: data })); "
            "});",
      );
      await jsonServer.on('connection', jsonHandler);

      final ws = await WebSocket.connect('ws://localhost:$jPort');
      final completer = Completer<Map<String, dynamic>>();
      ws.listen((data) {
        if (!completer.isCompleted) {
          completer
              .complete(jsonDecode(data.toString()) as Map<String, dynamic>);
        }
      });
      ws.add(jsonEncode({'type': 'add', 'a': 10, 'b': 20}));

      final response =
          await completer.future.timeout(const Duration(seconds: 5));
      await ws.close();
      await jsonServer.close();

      expect(response['type'], equals('response'));
      expect(response['result'], equals(30));
      expect(response['original']['a'], equals(10));
    });

    test('WebSocket — broadcast to all clients', () async {
      final dynamic wsMod = await js.require('ws');
      dynamic WSS = await wsMod.WebSocketServer;
      dynamic bcastSrv = await WSS.$new([
        {'port': 0}
      ]);
      await js.setGlobal('__bcastSrv', bcastSrv);

      for (var i = 0; i < 100; i++) {
        final a = await bcastSrv.address();
        if (a != null) break;
      }
      dynamic addr = await bcastSrv.address();
      final bPort = await addr.port;

      // Broadcast handler — readyState 1 = OPEN
      final bcastHandler = await js.createFunction(
        params: ['ws'],
        body: "ws.on('message', function(msg) { "
            "globalThis.__bcastSrv.clients.forEach(function(client) { "
            "  if (client.readyState === 1) client.send('broadcast: ' + msg.toString()); "
            "}); "
            "});",
      );
      await bcastSrv.on('connection', bcastHandler);

      // Two Dart WebSocket clients
      final ws1 = await WebSocket.connect('ws://localhost:$bPort');
      final ws2 = await WebSocket.connect('ws://localhost:$bPort');
      final c1Msgs = <String>[];
      final c2Msgs = <String>[];
      final c1Done = Completer<void>();
      final c2Done = Completer<void>();

      ws1.listen((data) {
        c1Msgs.add(data.toString());
        if (!c1Done.isCompleted) c1Done.complete();
      });
      ws2.listen((data) {
        c2Msgs.add(data.toString());
        if (!c2Done.isCompleted) c2Done.complete();
      });

      // Let connections establish
      await Future.delayed(const Duration(milliseconds: 200));
      ws1.add('hello all');
      await Future.wait([c1Done.future, c2Done.future])
          .timeout(const Duration(seconds: 5));

      await ws1.close();
      await ws2.close();
      await bcastSrv.close();

      expect(c1Msgs.length, equals(1));
      expect(c2Msgs.length, equals(1));
      expect(c1Msgs[0], contains('broadcast: hello all'));
      expect(c2Msgs[0], contains('broadcast: hello all'));
    });

    test('clean up WebSocket server', () async {
      if (wsServer != null) {
        await wsServer.close();
        wsServer = null;
      }
      expect(wsServer, isNull);
    });
  });
}
