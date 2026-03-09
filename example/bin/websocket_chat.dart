// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';

/// ═══════════════════════════════════════════════════════════════
///  WebSocket Real-Time Chat — Node.js ws server + Dart clients
/// ═══════════════════════════════════════════════════════════════
///
/// This example creates a WebSocket chat server using the `ws` npm
/// package, then connects multiple Dart clients to demonstrate
/// real-time bidirectional communication — all from Dart.
///
/// What you'll see:
///   1. Create a WebSocket server with `ws` npm package
///   2. Handle connections and messages via createFunction
///   3. Connect native Dart WebSocket clients
///   4. Broadcast messages between clients
///   5. JSON message exchange
///
/// Setup:
///   dart run flutter_js_bridger init
///   dart run flutter_js_bridger add ws
///
/// Run:
///   dart run example/bin/websocket_chat.dart
void main() async {
  final js = JsBridge();

  try {
    await js.initialize();
    print('🔌 flutter_js_bridger — WebSocket Chat Example\n');

    // ──────────────────────────────────────────────────
    //  Step 1: Import ws and create the server
    // ──────────────────────────────────────────────────
    print('Step 1: Creating WebSocket server...');
    dynamic wsMod = await js.require('ws');
    dynamic WSS = await wsMod.WebSocketServer;
    dynamic server = await WSS.$new([
      {'port': 0}
    ]);

    // Wait for the server to bind
    int? port;
    for (var i = 0; i < 100; i++) {
      final a = await server.address();
      if (a != null) {
        port = (await a.port) as int;
        break;
      }
    }
    print('  ✓ WebSocket server running on ws://localhost:$port');

    // ──────────────────────────────────────────────────
    //  Step 2: Set up connection handler — broadcasts to all
    // ──────────────────────────────────────────────────
    print('\nStep 2: Setting up broadcast handler...');

    // Store server reference so the handler can access it
    await js.setGlobal('__chatServer', server);

    final connectionHandler = await js.createFunction(
      params: ['ws'],
      body: '''
        ws.send(JSON.stringify({ type: 'system', text: 'Welcome to the chat!' }));

        ws.on('message', function(raw) {
          var msg = JSON.parse(raw.toString());
          msg.type = 'broadcast';

          var wss = globalThis.__chatServer;
          wss.clients.forEach(function(client) {
            if (client.readyState === 1) {
              client.send(JSON.stringify(msg));
            }
          });
        });
      ''',
    );
    await server.on('connection', connectionHandler);
    print('  ✓ Connection handler registered (broadcasts to all clients)');

    // ──────────────────────────────────────────────────
    //  Step 3: Connect two Dart WebSocket clients
    // ──────────────────────────────────────────────────
    print('\nStep 3: Connecting clients...\n');

    final wsUrl = 'ws://localhost:$port';

    // --- Alice connects ---
    final alice = await WebSocket.connect(wsUrl);
    final aliceMessages = <Map<String, dynamic>>[];
    final aliceWelcome = Completer<void>();
    final aliceGotBroadcast = Completer<void>();

    alice.listen((data) {
      final msg = jsonDecode(data.toString()) as Map<String, dynamic>;
      aliceMessages.add(msg);
      if (msg['type'] == 'system' && !aliceWelcome.isCompleted) {
        aliceWelcome.complete();
      }
      if (msg['type'] == 'broadcast' && !aliceGotBroadcast.isCompleted) {
        aliceGotBroadcast.complete();
      }
    });
    await aliceWelcome.future.timeout(const Duration(seconds: 5));
    print('  Alice connected — received: "${aliceMessages.last['text']}"');

    // --- Bob connects ---
    final bob = await WebSocket.connect(wsUrl);
    final bobMessages = <Map<String, dynamic>>[];
    final bobWelcome = Completer<void>();
    final bobGotBroadcast = Completer<void>();

    bob.listen((data) {
      final msg = jsonDecode(data.toString()) as Map<String, dynamic>;
      bobMessages.add(msg);
      if (msg['type'] == 'system' && !bobWelcome.isCompleted) {
        bobWelcome.complete();
      }
      if (msg['type'] == 'broadcast' && !bobGotBroadcast.isCompleted) {
        bobGotBroadcast.complete();
      }
    });
    await bobWelcome.future.timeout(const Duration(seconds: 5));
    print('  Bob connected — received: "${bobMessages.last['text']}"');

    // ──────────────────────────────────────────────────
    //  Step 4: Alice sends a message — both receive it
    // ──────────────────────────────────────────────────
    print('\nStep 4: Alice sends a message...');
    alice.add(jsonEncode({'user': 'Alice', 'text': 'Hello everyone!'}));

    await aliceGotBroadcast.future.timeout(const Duration(seconds: 5));
    await bobGotBroadcast.future.timeout(const Duration(seconds: 5));

    print('  Alice sent: "Hello everyone!"');
    print(
        '  ✓ Alice received broadcast (${aliceMessages.length} total messages)');
    print('  ✓ Bob received broadcast (${bobMessages.length} total messages)');

    // ──────────────────────────────────────────────────
    //  Step 5: Bob replies
    // ──────────────────────────────────────────────────
    print('\nStep 5: Bob replies...');
    bob.add(jsonEncode({'user': 'Bob', 'text': 'Hey Alice, welcome!'}));
    await Future.delayed(const Duration(milliseconds: 500));
    print('  Bob sent: "Hey Alice, welcome!"');

    // ──────────────────────────────────────────────────
    //  Step 6: Show full chat log
    // ──────────────────────────────────────────────────
    print('\n─── Alice\'s chat log ───');
    for (final msg in aliceMessages) {
      final prefix = msg['type'] == 'system' ? '[SYSTEM]' : '[${msg['user']}]';
      print('  $prefix ${msg['text']}');
    }
    print('\n─── Bob\'s chat log ───');
    for (final msg in bobMessages) {
      final prefix = msg['type'] == 'system' ? '[SYSTEM]' : '[${msg['user']}]';
      print('  $prefix ${msg['text']}');
    }

    // ──────────────────────────────────────────────────
    //  Step 7: Clean up
    // ──────────────────────────────────────────────────
    print('\nStep 6: Shutting down...');
    await alice.close();
    await bob.close();
    await server.close();
    print('  ✓ All connections closed');

    print('\n══════════════════════════════════════════════════════');
    print(' WebSocket Chat — JS server + Dart clients, zero JS!');
    print('══════════════════════════════════════════════════════');
  } finally {
    await js.dispose();
  }
}
