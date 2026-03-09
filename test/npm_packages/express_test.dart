import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

import '../helpers/npm_test_helper.dart';

/// Tests for Express.js — building a real REST API entirely from Dart.
///
/// **ZERO eval** — every line is pure Dart using the bridge proxy API:
///   - `js.require('express')` to import the package
///   - `express()` to create the app (invoke as function)
///   - `app.use(middleware)` to apply middleware
///   - `app.get(path, handler)` to define routes with Dart callbacks
///   - `app.listen(port)` to start the server
///   - All CRUD state stored in a Dart List, all logic in Dart
///   - All method calls go through the bridge's dynamic proxy — no eval!
void main() {
  late JsBridge js;

  setUpAll(() async {
    js = await createNpmTestBridge();
    await ensureAllInstalled(js, ['express', 'cors', 'morgan']);
  });

  tearDownAll(() async {
    await js.dispose();
  });

  // ═══════════════════════════════════════════════════════
  //  Step 1: Import Express — js.require() instead of eval
  // ═══════════════════════════════════════════════════════

  group('Step 1 — Import Express like a Dart library', () {
    test('require express — returns a callable function', () async {
      // Like: import express from 'express';
      dynamic express = await js.require('express');
      expect(express, isNotNull);

      final type = await express.$typeof();
      expect(type, equals('function'));
    });

    test('require cors — returns middleware factory', () async {
      dynamic cors = await js.require('cors');
      expect(cors, isNotNull);
      final type = await cors.$typeof();
      expect(type, equals('function'));
    });

    test('express() — create app by invoking the module', () async {
      dynamic express = await js.require('express');

      dynamic app = await express();
      expect(app, isNotNull);

      final hasGet = await app.$has('get');
      final hasPost = await app.$has('post');
      final hasPut = await app.$has('put');
      final hasDelete = await app.$has('delete');
      final hasUse = await app.$has('use');
      final hasListen = await app.$has('listen');

      expect(hasGet, isTrue);
      expect(hasPost, isTrue);
      expect(hasPut, isTrue);
      expect(hasDelete, isTrue);
      expect(hasUse, isTrue);
      expect(hasListen, isTrue);
    });

    test('express.json() — access static methods', () async {
      dynamic express = await js.require('express');

      dynamic jsonParser = await express.json();
      expect(jsonParser, isNotNull);
      final type = await jsonParser.$typeof();
      expect(type, equals('function'));
    });

    test('express.urlencoded() — another static method', () async {
      dynamic express = await js.require('express');

      dynamic urlParser = await express.urlencoded({'extended': true});
      expect(urlParser, isNotNull);
    });

    test('express.Router() — create a sub-router from Dart', () async {
      dynamic express = await js.require('express');

      dynamic router = await express.Router();
      expect(router, isNotNull);

      final hasGet = await router.$has('get');
      final hasPost = await router.$has('post');
      final hasUse = await router.$has('use');
      expect(hasGet, isTrue);
      expect(hasPost, isTrue);
      expect(hasUse, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Step 2: Middleware — apply from Dart
  // ═══════════════════════════════════════════════════════

  group('Step 2 — Middleware from Dart', () {
    test('app.use(cors()) — apply CORS middleware', () async {
      dynamic express = await js.require('express');
      dynamic cors = await js.require('cors');
      dynamic app = await express();

      dynamic corsMiddleware = await cors();
      await app.use(corsMiddleware);

      final keys = await app.$keys();
      expect(keys, isA<List<dynamic>>());
    });

    test('app.use(express.json()) — body parser from Dart', () async {
      dynamic express = await js.require('express');
      dynamic app = await express();

      dynamic jsonParser = await express.json();
      await app.use(jsonParser);

      dynamic urlParser = await express.urlencoded({'extended': true});
      await app.use(urlParser);

      expect(true, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Step 3: Define routes with Dart callbacks as handlers
  // ═══════════════════════════════════════════════════════

  group('Step 3 — Route handlers as Dart functions', () {
    late int port;

    test('define GET route and start server', () async {
      dynamic express = await js.require('express');
      dynamic app = await express();

      // Register a GET route with a Dart handler
      await app.get('/hello', (req, res) {
        res.json({'message': 'Hello from Dart!'});
      });

      // Start the server using the bridge API
      dynamic server = await app.listen(0);
      await Future.delayed(const Duration(milliseconds: 300));

      dynamic addr = await server.address();
      port = await addr.port as int;

      expect(port, greaterThan(0));

      // Now make a real HTTP request from Dart
      final client = HttpClient();
      try {
        final request =
            await client.getUrl(Uri.parse('http://localhost:$port/hello'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(response.statusCode, equals(200));
        expect(data['message'], equals('Hello from Dart!'));
      } finally {
        client.close();
        await server.close();
      }
    });

    test('Dart callback receives req and res as JsObject proxies', () async {
      dynamic express = await js.require('express');
      dynamic app = await express();

      await app.get('/echo-method', (req, res) {
        req.method.then((method) {
          res.json({'method': method, 'source': 'dart-callback'});
        });
      });

      dynamic server = await app.listen(0);
      await Future.delayed(const Duration(milliseconds: 300));
      dynamic addr = await server.address();
      final port = await addr.port as int;

      final client = HttpClient();
      try {
        final request = await client
            .getUrl(Uri.parse('http://localhost:$port/echo-method'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(data['method'], equals('GET'));
        expect(data['source'], equals('dart-callback'));
      } finally {
        client.close();
        await server.close();
      }
    });

    test('POST route — read req.body from Dart', () async {
      dynamic express = await js.require('express');
      dynamic app = await express();
      await app.use(await express.json());

      await app.post('/echo', (req, res) {
        req.body.then((body) {
          body.$toJson().then((jsonStr) {
            final parsed = jsonDecode(jsonStr as String);
            res.json({'received': parsed});
          });
        });
      });

      dynamic server = await app.listen(0);
      await Future.delayed(const Duration(milliseconds: 300));
      dynamic addr = await server.address();
      final port = await addr.port as int;

      final client = HttpClient();
      try {
        final request =
            await client.postUrl(Uri.parse('http://localhost:$port/echo'));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'name': 'Dart', 'version': 3}));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(data['received']['name'], equals('Dart'));
        expect(data['received']['version'], equals(3));
      } finally {
        client.close();
        await server.close();
      }
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Step 4: Full CRUD REST API from Dart
  // ═══════════════════════════════════════════════════════

  group('Step 4 — Full CRUD REST API', () {
    late int apiPort;
    late dynamic apiServer;

    // ── All state lives in Dart, not in JS ──
    final todos = <Map<String, dynamic>>[
      {'id': 1, 'title': 'Learn Dart', 'completed': true},
      {'id': 2, 'title': 'Learn Flutter', 'completed': false},
      {'id': 3, 'title': 'Build Bridge', 'completed': false},
    ];
    var nextId = 4;

    test('build complete Express API from Dart', () async {
      dynamic express = await js.require('express');
      dynamic cors = await js.require('cors');

      dynamic app = await express();
      await app.use(await cors());
      await app.use(await express.json());
      await app.use(await express.urlencoded({'extended': true}));

      // --- GET /api/health ---
      await app.get('/api/health', (req, res) {
        res.json({'status': 'ok', 'engine': 'bridger'});
      });

      // --- GET /api/todos --- state from Dart List
      await app.get('/api/todos', (req, res) {
        res.json(todos);
      });

      // --- GET /api/todos/:id --- lookup in Dart List
      await app.get('/api/todos/:id', (req, res) {
        req.params.then((params) {
          params.$toJson().then((pJson) {
            final id = int.parse(jsonDecode(pJson as String)['id'].toString());
            final matches = todos.where((t) => t['id'] == id).toList();
            if (matches.isEmpty) {
              res.status(404).then((_) => res.json({'error': 'Not found'}));
            } else {
              res.json(matches.first);
            }
          });
        });
      });

      // --- POST /api/todos --- create with Dart logic
      await app.post('/api/todos', (req, res) {
        req.body.then((body) {
          body.$toJson().then((bJson) {
            final parsed = jsonDecode(bJson as String);
            final title = parsed['title'];
            if (title == null) {
              res
                  .status(400)
                  .then((_) => res.json({'error': 'Title required'}));
              return;
            }
            final todo = {
              'id': nextId++,
              'title': title.toString(),
              'completed': false,
            };
            todos.add(todo);
            res.status(201).then((_) => res.json(todo));
          });
        });
      });

      // --- PUT /api/todos/:id --- update with Dart logic
      await app.put('/api/todos/:id', (req, res) {
        req.params.then((params) {
          params.$toJson().then((pJson) {
            final id = int.parse(jsonDecode(pJson as String)['id'].toString());
            req.body.then((body) {
              body.$toJson().then((bJson) {
                final updates = jsonDecode(bJson as String) as Map;
                final idx = todos.indexWhere((t) => t['id'] == id);
                if (idx == -1) {
                  res.status(404).then((_) => res.json({'error': 'Not found'}));
                  return;
                }
                if (updates.containsKey('title')) {
                  todos[idx]['title'] = updates['title'];
                }
                if (updates.containsKey('completed')) {
                  todos[idx]['completed'] = updates['completed'];
                }
                res.json(todos[idx]);
              });
            });
          });
        });
      });

      // --- DELETE /api/todos/:id --- remove from Dart List
      await app.delete('/api/todos/:id', (req, res) {
        req.params.then((params) {
          params.$toJson().then((pJson) {
            final id = int.parse(jsonDecode(pJson as String)['id'].toString());
            final idx = todos.indexWhere((t) => t['id'] == id);
            if (idx == -1) {
              res.status(404).then((_) => res.json({'error': 'Not found'}));
            } else {
              todos.removeAt(idx);
              res.json({'deleted': true});
            }
          });
        });
      });

      // --- Start server ---
      apiServer = await app.listen(0);
      await Future.delayed(const Duration(milliseconds: 300));
      dynamic addr = await apiServer.address();
      apiPort = await addr.port as int;

      expect(apiPort, greaterThan(0));
    });

    test('GET /api/health', () async {
      final client = HttpClient();
      try {
        final request = await client
            .getUrl(Uri.parse('http://localhost:$apiPort/api/health'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(response.statusCode, equals(200));
        expect(data['status'], equals('ok'));
        expect(data['engine'], equals('bridger'));
      } finally {
        client.close();
      }
    });

    test('GET /api/todos — list all', () async {
      final client = HttpClient();
      try {
        final request = await client
            .getUrl(Uri.parse('http://localhost:$apiPort/api/todos'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as List;

        expect(response.statusCode, equals(200));
        expect(data.length, equals(3));
        expect(data[0]['title'], equals('Learn Dart'));
      } finally {
        client.close();
      }
    });

    test('GET /api/todos/2 — single todo', () async {
      final client = HttpClient();
      try {
        final request = await client
            .getUrl(Uri.parse('http://localhost:$apiPort/api/todos/2'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(response.statusCode, equals(200));
        expect(data['id'], equals(2));
        expect(data['title'], equals('Learn Flutter'));
        expect(data['completed'], isFalse);
      } finally {
        client.close();
      }
    });

    test('GET /api/todos/999 — 404', () async {
      final client = HttpClient();
      try {
        final request = await client
            .getUrl(Uri.parse('http://localhost:$apiPort/api/todos/999'));
        final response = await request.close();
        await response.drain<void>();

        expect(response.statusCode, equals(404));
      } finally {
        client.close();
      }
    });

    test('POST /api/todos — create', () async {
      final client = HttpClient();
      try {
        final request = await client
            .postUrl(Uri.parse('http://localhost:$apiPort/api/todos'));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'title': 'Test from Dart'}));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(response.statusCode, equals(201));
        expect(data['id'], equals(4));
        expect(data['title'], equals('Test from Dart'));
        expect(data['completed'], isFalse);
      } finally {
        client.close();
      }
    });

    test('POST /api/todos — 400 missing title', () async {
      final client = HttpClient();
      try {
        final request = await client
            .postUrl(Uri.parse('http://localhost:$apiPort/api/todos'));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({}));
        final response = await request.close();
        await response.drain<void>();

        expect(response.statusCode, equals(400));
      } finally {
        client.close();
      }
    });

    test('PUT /api/todos/2 — update', () async {
      final client = HttpClient();
      try {
        final request = await client
            .putUrl(Uri.parse('http://localhost:$apiPort/api/todos/2'));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'completed': true}));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(response.statusCode, equals(200));
        expect(data['completed'], isTrue);
        expect(data['title'], equals('Learn Flutter'));
      } finally {
        client.close();
      }
    });

    test('DELETE /api/todos/1 — delete', () async {
      final client = HttpClient();
      try {
        final request = await client
            .deleteUrl(Uri.parse('http://localhost:$apiPort/api/todos/1'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(response.statusCode, equals(200));
        expect(data['deleted'], isTrue);
      } finally {
        client.close();
      }
    });

    test('verify delete took effect', () async {
      final client = HttpClient();
      try {
        final request = await client
            .getUrl(Uri.parse('http://localhost:$apiPort/api/todos'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as List;

        // Started with 3, added 1, deleted 1 = 3
        expect(data.length, equals(3));
        expect(data.every((t) => t['id'] != 1), isTrue);
      } finally {
        client.close();
      }
    });

    test('CORS headers present', () async {
      final client = HttpClient();
      try {
        final request = await client
            .getUrl(Uri.parse('http://localhost:$apiPort/api/health'));
        request.headers.set('Origin', 'http://example.com');
        final response = await request.close();
        await response.drain<void>();

        final corsHeader =
            response.headers.value('access-control-allow-origin');
        expect(corsHeader, isNotNull);
      } finally {
        client.close();
      }
    });

    test('shut down server', () async {
      await apiServer.close();
      final client = HttpClient();
      try {
        await client
            .getUrl(Uri.parse('http://localhost:$apiPort/api/health'))
            .timeout(const Duration(seconds: 2));
        fail('Expected connection refused');
      } on SocketException {
        // Expected
      } on TimeoutException {
        // Also acceptable
      } finally {
        client.close();
      }
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Step 5: Express Router — modular routes from Dart
  // ═══════════════════════════════════════════════════════

  group('Step 5 — Express Router from Dart', () {
    test('create router, add routes, mount on app', () async {
      dynamic express = await js.require('express');
      dynamic app = await express();
      await app.use(await express.json());

      dynamic router = await express.Router();

      await router.get('/', (req, res) {
        res.json([
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'},
        ]);
      });

      await router.get('/:id', (req, res) {
        req.params.then((params) {
          params.$toJson().then((pJson) {
            final id = int.parse(jsonDecode(pJson as String)['id'].toString());
            if (id == 1) {
              res.json({'id': 1, 'name': 'Alice'});
            } else if (id == 2) {
              res.json({'id': 2, 'name': 'Bob'});
            } else {
              res.status(404).then((_) => res.json({'error': 'Not found'}));
            }
          });
        });
      });

      // Mount the router at /api/users
      await app.use('/api/users', router);

      dynamic server = await app.listen(0);
      await Future.delayed(const Duration(milliseconds: 300));
      dynamic addr = await server.address();
      final port = await addr.port as int;

      final client = HttpClient();
      try {
        // GET /api/users — list
        var request =
            await client.getUrl(Uri.parse('http://localhost:$port/api/users'));
        var response = await request.close();
        var body = await response.transform(utf8.decoder).join();
        var data = jsonDecode(body) as List;
        expect(data.length, equals(2));
        expect(data[0]['name'], equals('Alice'));

        // GET /api/users/1 — single
        request = await client
            .getUrl(Uri.parse('http://localhost:$port/api/users/1'));
        response = await request.close();
        body = await response.transform(utf8.decoder).join();
        final user = jsonDecode(body);
        expect(user['name'], equals('Alice'));

        // GET /api/users/999 — not found
        request = await client
            .getUrl(Uri.parse('http://localhost:$port/api/users/999'));
        response = await request.close();
        expect(response.statusCode, equals(404));
      } finally {
        client.close();
        await server.close();
      }
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Step 6: Query params and path params from Dart
  // ═══════════════════════════════════════════════════════

  group('Step 6 — Query and path params', () {
    test('read query params from req.query in Dart', () async {
      dynamic express = await js.require('express');
      dynamic app = await express();

      await app.get('/search', (req, res) {
        req.query.then((query) {
          query.$toJson().then((qJson) {
            final params = jsonDecode(qJson as String);
            res.json({
              'q': params['q'] ?? '',
              'page': params['page'] ?? '1',
            });
          });
        });
      });

      dynamic server = await app.listen(0);
      await Future.delayed(const Duration(milliseconds: 300));
      dynamic addr = await server.address();
      final port = await addr.port as int;

      final client = HttpClient();
      try {
        final request = await client
            .getUrl(Uri.parse('http://localhost:$port/search?q=dart&page=2'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(data['q'], equals('dart'));
        expect(data['page'], equals('2'));
      } finally {
        client.close();
        await server.close();
      }
    });

    test('read path params from req.params in Dart', () async {
      dynamic express = await js.require('express');
      dynamic app = await express();

      await app.get('/users/:userId/posts/:postId', (req, res) {
        req.params.then((params) {
          params.$toJson().then((pJson) {
            final p = jsonDecode(pJson as String);
            res.json({
              'userId': p['userId'],
              'postId': p['postId'],
            });
          });
        });
      });

      dynamic server = await app.listen(0);
      await Future.delayed(const Duration(milliseconds: 300));
      dynamic addr = await server.address();
      final port = await addr.port as int;

      final client = HttpClient();
      try {
        final request = await client
            .getUrl(Uri.parse('http://localhost:$port/users/42/posts/7'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(data['userId'], equals('42'));
        expect(data['postId'], equals('7'));
      } finally {
        client.close();
        await server.close();
      }
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Step 7: Response methods — all called from Dart
  // ═══════════════════════════════════════════════════════

  group('Step 7 — Response methods from Dart', () {
    test('res.json() — send JSON', () async {
      dynamic express = await js.require('express');
      dynamic app = await express();

      await app.get('/json', (req, res) {
        res.json({'type': 'json', 'ok': true});
      });

      dynamic server = await app.listen(0);
      await Future.delayed(const Duration(milliseconds: 300));
      dynamic addr = await server.address();
      final port = await addr.port as int;

      final client = HttpClient();
      try {
        final request =
            await client.getUrl(Uri.parse('http://localhost:$port/json'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(data['type'], equals('json'));
        expect(data['ok'], isTrue);
      } finally {
        client.close();
        await server.close();
      }
    });

    test('res.send() — send plain text', () async {
      dynamic express = await js.require('express');
      dynamic app = await express();

      await app.get('/text', (req, res) {
        res.send('Hello plain text');
      });

      dynamic server = await app.listen(0);
      await Future.delayed(const Duration(milliseconds: 300));
      dynamic addr = await server.address();
      final port = await addr.port as int;

      final client = HttpClient();
      try {
        final request =
            await client.getUrl(Uri.parse('http://localhost:$port/text'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();

        expect(body, equals('Hello plain text'));
      } finally {
        client.close();
        await server.close();
      }
    });

    test('res.status().json() — custom status code', () async {
      dynamic express = await js.require('express');
      dynamic app = await express();

      await app.get('/created', (req, res) {
        res.status(201).then((_) => res.json({'created': true}));
      });

      dynamic server = await app.listen(0);
      await Future.delayed(const Duration(milliseconds: 300));
      dynamic addr = await server.address();
      final port = await addr.port as int;

      final client = HttpClient();
      try {
        final request =
            await client.getUrl(Uri.parse('http://localhost:$port/created'));
        final response = await request.close();

        expect(response.statusCode, equals(201));
      } finally {
        client.close();
        await server.close();
      }
    });

    test('res.set() — custom response header', () async {
      dynamic express = await js.require('express');
      dynamic app = await express();

      await app.get('/header', (req, res) {
        res.set('X-Powered-By', 'bridger').then((_) {
          res.json({'ok': true});
        });
      });

      dynamic server = await app.listen(0);
      await Future.delayed(const Duration(milliseconds: 300));
      dynamic addr = await server.address();
      final port = await addr.port as int;

      final client = HttpClient();
      try {
        final request =
            await client.getUrl(Uri.parse('http://localhost:$port/header'));
        final response = await request.close();

        expect(
          response.headers.value('x-powered-by'),
          equals('bridger'),
        );
      } finally {
        client.close();
        await server.close();
      }
    });
  });
}
