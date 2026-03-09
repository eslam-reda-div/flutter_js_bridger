// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';

/// ═══════════════════════════════════════════════════════════════
///  Express.js CRUD REST API — Built entirely from Dart
/// ═══════════════════════════════════════════════════════════════
///
/// This example builds a complete REST API with Express.js, but
/// every single line is written in Dart — no JavaScript code at all.
///
/// What you'll see:
///   1. Import Express like a Dart library
///   2. Create an app and apply middleware (CORS, JSON parser)
///   3. Define GET/POST/PUT/DELETE routes with Dart callbacks
///   4. Store all state in a Dart List (not JS)
///   5. Make real HTTP requests to test the API
///   6. Gracefully shut down the server
///
/// Setup:
///   dart run flutter_js_bridger init
///   dart run flutter_js_bridger add express cors
///
/// Run:
///   dart run example/bin/express_crud_api.dart
void main() async {
  final js = JsBridge();

  try {
    await js.initialize();
    print('🚀 flutter_js_bridger — Express.js CRUD API Example\n');

    // ──────────────────────────────────────────────────
    //  Step 1: Import packages — just like Dart imports
    // ──────────────────────────────────────────────────
    print('Step 1: Importing Express and CORS...');
    dynamic express = await js.require('express');
    dynamic cors = await js.require('cors');
    print('  ✓ express imported (type: ${await express.$typeof()})');
    print('  ✓ cors imported (type: ${await cors.$typeof()})');

    // ──────────────────────────────────────────────────
    //  Step 2: Create the app and apply middleware
    // ──────────────────────────────────────────────────
    print('\nStep 2: Creating Express app with middleware...');
    dynamic app = await express();
    await app.use(await cors());
    await app.use(await express.json());
    print('  ✓ Express app created');
    print('  ✓ CORS middleware applied');
    print('  ✓ JSON body parser applied');

    // ──────────────────────────────────────────────────
    //  Step 3: Define our data — all in Dart!
    // ──────────────────────────────────────────────────
    final books = <Map<String, dynamic>>[
      {
        'id': 1,
        'title': 'The Dart Programming Language',
        'author': 'Gilad Bracha',
        'year': 2015
      },
      {
        'id': 2,
        'title': 'Flutter in Action',
        'author': 'Eric Windmill',
        'year': 2020
      },
      {
        'id': 3,
        'title': 'Clean Code',
        'author': 'Robert C. Martin',
        'year': 2008
      },
    ];
    var nextId = 4;

    // ──────────────────────────────────────────────────
    //  Step 4: Define routes — Dart callbacks handle requests
    // ──────────────────────────────────────────────────
    print('\nStep 3: Defining REST routes...');

    // GET /api/books — list all books
    await app.get('/api/books', (req, res) {
      res.json(books);
    });
    print('  ✓ GET    /api/books');

    // GET /api/books/:id — get a single book
    await app.get('/api/books/:id', (req, res) {
      req.params.then((params) {
        params.$toJson().then((pJson) {
          final id = int.parse(jsonDecode(pJson as String)['id'].toString());
          final matches = books.where((b) => b['id'] == id).toList();
          if (matches.isEmpty) {
            res.status(404).then((_) => res.json({'error': 'Book not found'}));
          } else {
            res.json(matches.first);
          }
        });
      });
    });
    print('  ✓ GET    /api/books/:id');

    // POST /api/books — add a new book
    await app.post('/api/books', (req, res) {
      req.body.then((body) {
        body.$toJson().then((bJson) {
          final data = jsonDecode(bJson as String);
          if (data['title'] == null) {
            res
                .status(400)
                .then((_) => res.json({'error': 'Title is required'}));
            return;
          }
          final book = {
            'id': nextId++,
            'title': data['title'],
            'author': data['author'] ?? 'Unknown',
            'year': data['year'] ?? DateTime.now().year,
          };
          books.add(book);
          res.status(201).then((_) => res.json(book));
        });
      });
    });
    print('  ✓ POST   /api/books');

    // PUT /api/books/:id — update a book
    await app.put('/api/books/:id', (req, res) {
      req.params.then((params) {
        params.$toJson().then((pJson) {
          final id = int.parse(jsonDecode(pJson as String)['id'].toString());
          req.body.then((body) {
            body.$toJson().then((bJson) {
              final updates = jsonDecode(bJson as String) as Map;
              final idx = books.indexWhere((b) => b['id'] == id);
              if (idx == -1) {
                res
                    .status(404)
                    .then((_) => res.json({'error': 'Book not found'}));
                return;
              }
              if (updates.containsKey('title'))
                books[idx]['title'] = updates['title'];
              if (updates.containsKey('author'))
                books[idx]['author'] = updates['author'];
              if (updates.containsKey('year'))
                books[idx]['year'] = updates['year'];
              res.json(books[idx]);
            });
          });
        });
      });
    });
    print('  ✓ PUT    /api/books/:id');

    // DELETE /api/books/:id — remove a book
    await app.delete('/api/books/:id', (req, res) {
      req.params.then((params) {
        params.$toJson().then((pJson) {
          final id = int.parse(jsonDecode(pJson as String)['id'].toString());
          final idx = books.indexWhere((b) => b['id'] == id);
          if (idx == -1) {
            res.status(404).then((_) => res.json({'error': 'Book not found'}));
          } else {
            final removed = books.removeAt(idx);
            res.json({'deleted': true, 'book': removed});
          }
        });
      });
    });
    print('  ✓ DELETE /api/books/:id');

    // ──────────────────────────────────────────────────
    //  Step 5: Start the server
    // ──────────────────────────────────────────────────
    print('\nStep 4: Starting server...');
    dynamic server = await app.listen(0);
    await Future.delayed(const Duration(milliseconds: 300));
    dynamic addr = await server.address();
    final port = await addr.port as int;
    print('  ✓ Server running at http://localhost:$port\n');

    // ──────────────────────────────────────────────────
    //  Step 6: Test the API with real HTTP requests
    // ──────────────────────────────────────────────────
    final baseUrl = 'http://localhost:$port/api/books';
    final client = HttpClient();

    try {
      // --- List all books ---
      print('Testing: GET /api/books');
      var request = await client.getUrl(Uri.parse(baseUrl));
      var response = await request.close();
      var body = await response.transform(utf8.decoder).join();
      var data = jsonDecode(body);
      print('  → ${response.statusCode}: ${(data as List).length} books found');
      for (final book in data) {
        print('    - "${book['title']}" by ${book['author']}');
      }

      // --- Get single book ---
      print('\nTesting: GET /api/books/1');
      request = await client.getUrl(Uri.parse('$baseUrl/1'));
      response = await request.close();
      body = await response.transform(utf8.decoder).join();
      data = jsonDecode(body);
      print('  → ${response.statusCode}: "${data['title']}"');

      // --- Create a new book ---
      print('\nTesting: POST /api/books');
      request = await client.postUrl(Uri.parse(baseUrl));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'title': 'Effective Dart',
        'author': 'Dart Team',
        'year': 2024,
      }));
      response = await request.close();
      body = await response.transform(utf8.decoder).join();
      data = jsonDecode(body);
      print(
          '  → ${response.statusCode}: Created book #${data['id']} — "${data['title']}"');

      // --- Update a book ---
      print('\nTesting: PUT /api/books/2');
      request = await client.putUrl(Uri.parse('$baseUrl/2'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'year': 2021}));
      response = await request.close();
      body = await response.transform(utf8.decoder).join();
      data = jsonDecode(body);
      print(
          '  → ${response.statusCode}: Updated — "${data['title']}" now year ${data['year']}');

      // --- Delete a book ---
      print('\nTesting: DELETE /api/books/3');
      request = await client.deleteUrl(Uri.parse('$baseUrl/3'));
      response = await request.close();
      body = await response.transform(utf8.decoder).join();
      data = jsonDecode(body);
      print('  → ${response.statusCode}: Deleted "${data['book']['title']}"');

      // --- Verify final state ---
      print('\nTesting: GET /api/books (final state)');
      request = await client.getUrl(Uri.parse(baseUrl));
      response = await request.close();
      body = await response.transform(utf8.decoder).join();
      data = jsonDecode(body);
      print('  → ${(data as List).length} books remaining:');
      for (final book in data) {
        print(
            '    - #${book['id']} "${book['title']}" by ${book['author']} (${book['year']})');
      }

      // --- 404 test ---
      print('\nTesting: GET /api/books/999 (not found)');
      request = await client.getUrl(Uri.parse('$baseUrl/999'));
      response = await request.close();
      body = await response.transform(utf8.decoder).join();
      print('  → ${response.statusCode}: ${jsonDecode(body)['error']}');
    } finally {
      client.close();
    }

    // ──────────────────────────────────────────────────
    //  Step 7: Shut down
    // ──────────────────────────────────────────────────
    print('\nStep 5: Shutting down server...');
    await server.close();
    print('  ✓ Server stopped');

    print('\n════════════════════════════════════════════');
    print(' Express CRUD API — all from Dart, zero JS!');
    print('════════════════════════════════════════════');
  } finally {
    await js.dispose();
  }
}
