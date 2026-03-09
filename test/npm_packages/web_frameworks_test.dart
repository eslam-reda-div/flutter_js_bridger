import 'dart:convert';
import 'dart:io';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

import '../helpers/npm_test_helper.dart';

/// Tests for Fastify and Koa — alternative web frameworks.
///
/// Uses Dart-native proxy API — zero eval. Route handlers and middleware
/// use createFunction for synchronous JS callbacks.
void main() {
  late JsBridge js;
  dynamic fastifyApp;
  int? fastifyPort;
  dynamic koaServer;
  int? koaPort;

  setUpAll(() async {
    js = await createNpmTestBridge();
    await ensureAllInstalled(
        js, ['fastify', 'koa', 'koa-router', 'koa-bodyparser']);
  });

  tearDownAll(() async {
    try {
      if (fastifyApp != null) await fastifyApp.close();
      if (koaServer != null) await koaServer.close();
    } catch (_) {}
    await js.dispose();
  });

  // ─── Fastify ───────────────────────────────────────────────

  group('Fastify', () {
    test('require fastify', () async {
      final dynamic fastify = await js.require('fastify');
      expect(fastify, isNotNull);
      expect(fastify, isA<JsObject>());
    });

    test('create and start Fastify server with routes', () async {
      final dynamic Fastify = await js.require('fastify');
      dynamic app = await Fastify.$invoke([
        {'logger': false}
      ]);

      final helloHandler = await js.createFunction(
        params: ['request', 'reply'],
        body: "return { message: 'Hello from Fastify!' }",
      );
      await app.get('/api/hello', helloHandler);

      final userHandler = await js.createFunction(
        params: ['request', 'reply'],
        body:
            "return { userId: request.params.id, name: 'User ' + request.params.id }",
      );
      await app.get('/api/users/:id', userHandler);

      final echoHandler = await js.createFunction(
        params: ['request', 'reply'],
        body: 'return { received: request.body }',
      );
      await app.post('/api/echo', echoHandler);

      final queryHandler = await js.createFunction(
        params: ['request', 'reply'],
        body: 'return { params: request.query }',
      );
      await app.get('/api/query', queryHandler);

      final address = await app.listen({'port': 0});
      fastifyPort = Uri.parse(address as String).port;
      fastifyApp = app;
      expect(fastifyPort, isNotNull);
    });

    test('Fastify GET /api/hello', () async {
      final port = fastifyPort;
      final client = HttpClient();
      try {
        final request =
            await client.getUrl(Uri.parse('http://localhost:$port/api/hello'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(response.statusCode, equals(200));
        expect(data['message'], equals('Hello from Fastify!'));
      } finally {
        client.close();
      }
    });

    test('Fastify GET with params', () async {
      final port = fastifyPort;
      final client = HttpClient();
      try {
        final request = await client
            .getUrl(Uri.parse('http://localhost:$port/api/users/42'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(response.statusCode, equals(200));
        expect(data['userId'], equals('42'));
        expect(data['name'], equals('User 42'));
      } finally {
        client.close();
      }
    });

    test('Fastify POST with body', () async {
      final port = fastifyPort;
      final client = HttpClient();
      try {
        final request =
            await client.postUrl(Uri.parse('http://localhost:$port/api/echo'));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'hello': 'world'}));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(response.statusCode, equals(200));
        expect(data['received']['hello'], equals('world'));
      } finally {
        client.close();
      }
    });

    test('Fastify query params', () async {
      final port = fastifyPort;
      final client = HttpClient();
      try {
        final request = await client.getUrl(
            Uri.parse('http://localhost:$port/api/query?foo=bar&num=42'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(response.statusCode, equals(200));
        expect(data['params']['foo'], equals('bar'));
        expect(data['params']['num'], equals('42'));
      } finally {
        client.close();
      }
    });

    test('shutdown Fastify', () async {
      if (fastifyApp != null) {
        await fastifyApp.close();
        fastifyApp = null;
      }
      expect(fastifyApp, isNull);
    });
  });

  // ─── Koa ───────────────────────────────────────────────────

  group('Koa', () {
    test('require koa and koa-router', () async {
      final dynamic koa = await js.require('koa');
      expect(koa, isNotNull);
      expect(koa, isA<JsObject>());

      final dynamic router = await js.require('koa-router');
      expect(router, isNotNull);

      final dynamic bodyParser = await js.require('koa-bodyparser');
      expect(bodyParser, isNotNull);
    });

    test('create and start Koa server with routes', () async {
      final dynamic Koa = await js.require('koa');
      final dynamic Router = await js.require('koa-router');
      final dynamic bodyParserMod = await js.require('koa-bodyparser');

      dynamic app = await Koa.$new([]);
      dynamic router = await Router.$new([]);

      dynamic bpMiddleware = await bodyParserMod.$invoke([]);
      await app.use(bpMiddleware);

      final helloHandler = await js.createFunction(
        params: ['ctx'],
        body: "ctx.body = { message: 'Hello from Koa!' }",
      );
      await router.get('/api/hello', helloHandler);

      final itemGetHandler = await js.createFunction(
        params: ['ctx'],
        body: 'ctx.body = { itemId: ctx.params.id }',
      );
      await router.get('/api/items/:id', itemGetHandler);

      final itemPostHandler = await js.createFunction(
        params: ['ctx'],
        body: 'ctx.status = 201; ctx.body = { created: ctx.request.body }',
      );
      await router.post('/api/items', itemPostHandler);

      dynamic routes = await router.routes();
      await app.use(routes);
      dynamic allowed = await router.allowedMethods();
      await app.use(allowed);

      dynamic server = await app.listen(0);
      // Wait for server to be listening (IPC round-trips let event loop run)
      for (var i = 0; i < 100 && await server.listening != true; i++) {}
      dynamic addr = await server.address();
      koaPort = (await addr.port) as int;
      koaServer = server;
      expect(koaPort, isNotNull);
    });

    test('Koa GET /api/hello', () async {
      final port = koaPort;
      final client = HttpClient();
      try {
        final request =
            await client.getUrl(Uri.parse('http://localhost:$port/api/hello'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(response.statusCode, equals(200));
        expect(data['message'], equals('Hello from Koa!'));
      } finally {
        client.close();
      }
    });

    test('Koa GET with params', () async {
      final port = koaPort;
      final client = HttpClient();
      try {
        final request = await client
            .getUrl(Uri.parse('http://localhost:$port/api/items/99'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(response.statusCode, equals(200));
        expect(data['itemId'], equals('99'));
      } finally {
        client.close();
      }
    });

    test('Koa POST with body', () async {
      final port = koaPort;
      final client = HttpClient();
      try {
        final request =
            await client.postUrl(Uri.parse('http://localhost:$port/api/items'));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'name': 'Widget', 'price': 9.99}));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(response.statusCode, equals(201));
        expect(data['created']['name'], equals('Widget'));
      } finally {
        client.close();
      }
    });

    test('Koa middleware chain', () async {
      final dynamic Koa = await js.require('koa');
      dynamic app = await Koa.$new([]);

      await js.setGlobal('__mwLog', []);

      final mw1 = await js.createFunction(
        params: ['ctx', 'next'],
        body:
            "return (async () => { globalThis.__mwLog.push('before1'); await next(); globalThis.__mwLog.push('after1'); })()",
      );
      await app.use(mw1);

      final mw2 = await js.createFunction(
        params: ['ctx', 'next'],
        body:
            "return (async () => { globalThis.__mwLog.push('before2'); await next(); globalThis.__mwLog.push('after2'); })()",
      );
      await app.use(mw2);

      final handler = await js.createFunction(
        params: ['ctx'],
        body:
            "globalThis.__mwLog.push('handler'); ctx.body = { order: globalThis.__mwLog }",
      );
      await app.use(handler);

      dynamic mwServer = await app.listen(0);
      for (var i = 0; i < 100 && await mwServer.listening != true; i++) {}
      dynamic addr = await mwServer.address();
      final port = await addr.port;

      final client = HttpClient();
      try {
        final request =
            await client.getUrl(Uri.parse('http://localhost:$port/'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(data['order'], contains('before1'));
        expect(data['order'], contains('before2'));
        expect(data['order'], contains('handler'));
      } finally {
        client.close();
        await mwServer.close();
      }
    });

    test('shutdown Koa', () async {
      if (koaServer != null) {
        await koaServer.close();
        koaServer = null;
      }
      expect(koaServer, isNull);
    });
  });
}
