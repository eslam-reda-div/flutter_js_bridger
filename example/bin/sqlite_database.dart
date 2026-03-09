// ignore_for_file: avoid_print
import 'package:flutter_js_bridger/flutter_js_bridger.dart';

/// ═══════════════════════════════════════════════════════════════
///  SQLite Database — CRUD with better-sqlite3, from Dart
/// ═══════════════════════════════════════════════════════════════
///
/// This example demonstrates a complete SQLite database workflow
/// using better-sqlite3 — the fastest SQLite library for Node.js —
/// entirely from Dart. No JavaScript code written.
///
/// What you'll see:
///   1. Open an in-memory SQLite database
///   2. Create tables with SQL
///   3. Insert, query, update, and delete rows
///   4. Use prepared statements with parameters
///   5. Run transactions
///   6. Aggregation queries (COUNT, AVG, etc.)
///
/// Setup:
///   dart run flutter_js_bridger init
///   dart run flutter_js_bridger add better-sqlite3
///
/// Run:
///   dart run example/bin/sqlite_database.dart
void main() async {
  final js = JsBridge();

  try {
    await js.initialize();
    print('🗄️  flutter_js_bridger — SQLite Database Example\n');

    // ──────────────────────────────────────────────────
    //  Step 1: Open an in-memory database
    // ──────────────────────────────────────────────────
    print('Step 1: Opening SQLite database...');
    dynamic Database = await js.require('better-sqlite3');
    dynamic db = await Database(':memory:');
    print('  ✓ In-memory database opened');

    // ──────────────────────────────────────────────────
    //  Step 2: Create tables
    // ──────────────────────────────────────────────────
    print('\nStep 2: Creating tables...');
    await db.exec('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        age INTEGER,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    print('  ✓ users table created');

    await db.exec('''
      CREATE TABLE posts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        body TEXT,
        likes INTEGER DEFAULT 0,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');
    print('  ✓ posts table created');

    // ──────────────────────────────────────────────────
    //  Step 3: Insert data using prepared statements
    // ──────────────────────────────────────────────────
    print('\nStep 3: Inserting data...');

    dynamic insertUser = await db.prepare(
      'INSERT INTO users (name, email, age) VALUES (?, ?, ?)',
    );

    await insertUser.run('Alice', 'alice@example.com', 28);
    await insertUser.run('Bob', 'bob@example.com', 34);
    await insertUser.run('Charlie', 'charlie@example.com', 22);
    await insertUser.run('Diana', 'diana@example.com', 31);
    print('  ✓ 4 users inserted');

    dynamic insertPost = await db.prepare(
      'INSERT INTO posts (user_id, title, body, likes) VALUES (?, ?, ?, ?)',
    );

    await insertPost.run(
        1, 'Getting Started with Dart', 'Dart is awesome!', 42);
    await insertPost.run(1, 'Flutter Tips', 'Top 10 Flutter tips...', 89);
    await insertPost.run(2, 'Node.js Bridge', 'Using npm from Dart', 156);
    await insertPost.run(3, 'My First Post', 'Hello world!', 7);
    await insertPost.run(2, 'Advanced Bridge', 'Deep dive into bridger', 234);
    print('  ✓ 5 posts inserted');

    // ──────────────────────────────────────────────────
    //  Step 4: Query data
    // ──────────────────────────────────────────────────
    print('\nStep 4: Querying data...');

    // Get all users
    dynamic allUsers = await db.prepare('SELECT * FROM users').all();
    print('\n  All users:');
    for (var i = 0; i < (allUsers as List).length; i++) {
      dynamic user = allUsers[i];
      if (user is Map) {
        print(
            '    #${i + 1} ${user['name']} (${user['email']}) age ${user['age']}');
      } else {
        final name = await user.name;
        final email = await user.email;
        final age = await user.age;
        print('    #${i + 1} $name ($email) age $age');
      }
    }

    // Get single user
    dynamic alice =
        await db.prepare('SELECT * FROM users WHERE name = ?').get('Alice');
    if (alice is Map) {
      print('\n  Found user: ${alice['name']} (${alice['email']})');
    } else {
      final name = await alice.name;
      final email = await alice.email;
      print('\n  Found user: $name ($email)');
    }

    // Get posts with user names (JOIN)
    dynamic postsWithUsers = await db.prepare('''
      SELECT posts.title, posts.likes, users.name as author
      FROM posts
      JOIN users ON posts.user_id = users.id
      ORDER BY posts.likes DESC
    ''').all();

    print('\n  Posts by popularity:');
    for (var i = 0; i < (postsWithUsers as List).length; i++) {
      dynamic post = postsWithUsers[i];
      if (post is Map) {
        print(
            '    ${i + 1}. "${post['title']}" by ${post['author']} — ${post['likes']} likes');
      } else {
        final title = await post.title;
        final likes = await post.likes;
        final author = await post.author;
        print('    ${i + 1}. "$title" by $author — $likes likes');
      }
    }

    // ──────────────────────────────────────────────────
    //  Step 5: Update data
    // ──────────────────────────────────────────────────
    print('\nStep 5: Updating data...');

    dynamic updateLikes = await db.prepare(
      'UPDATE posts SET likes = likes + ? WHERE title = ?',
    );
    await updateLikes.run(100, 'My First Post');
    print('  ✓ Added 100 likes to "My First Post"');

    dynamic updateAge = await db.prepare(
      'UPDATE users SET age = ? WHERE name = ?',
    );
    await updateAge.run(29, 'Alice');
    print('  ✓ Updated Alice\'s age to 29');

    // ──────────────────────────────────────────────────
    //  Step 6: Delete data
    // ──────────────────────────────────────────────────
    print('\nStep 6: Deleting data...');

    await db.prepare('DELETE FROM posts WHERE title = ?').run('My First Post');
    print('  ✓ Deleted "My First Post"');

    dynamic remaining =
        await db.prepare('SELECT COUNT(*) as count FROM posts').get();
    if (remaining is Map) {
      print('  Remaining posts: ${remaining['count']}');
    } else {
      final count = await remaining.count;
      print('  Remaining posts: $count');
    }

    // ──────────────────────────────────────────────────
    //  Step 7: Aggregation queries
    // ──────────────────────────────────────────────────
    print('\nStep 7: Aggregation queries...');

    dynamic stats = await db.prepare('''
      SELECT
        COUNT(*) as total_posts,
        SUM(likes) as total_likes,
        AVG(likes) as avg_likes,
        MAX(likes) as max_likes,
        MIN(likes) as min_likes
      FROM posts
    ''').get();

    if (stats is Map) {
      print('  Total posts: ${stats['total_posts']}');
      print('  Total likes: ${stats['total_likes']}');
      print('  Avg likes:   ${stats['avg_likes']}');
      print('  Max likes:   ${stats['max_likes']}');
      print('  Min likes:   ${stats['min_likes']}');
    } else {
      print('  Total posts: ${await stats.total_posts}');
      print('  Total likes: ${await stats.total_likes}');
      print('  Avg likes:   ${await stats.avg_likes}');
      print('  Max likes:   ${await stats.max_likes}');
      print('  Min likes:   ${await stats.min_likes}');
    }

    // Posts per user
    dynamic postsPerUser = await db.prepare('''
      SELECT users.name, COUNT(posts.id) as post_count, COALESCE(SUM(posts.likes), 0) as total_likes
      FROM users
      LEFT JOIN posts ON users.id = posts.user_id
      GROUP BY users.id
      ORDER BY total_likes DESC
    ''').all();

    print('\n  Posts per user:');
    for (var i = 0; i < (postsPerUser as List).length; i++) {
      dynamic row = postsPerUser[i];
      if (row is Map) {
        print(
            '    ${row['name']}: ${row['post_count']} posts, ${row['total_likes']} total likes');
      } else {
        final name = await row.name;
        final postCount = await row.post_count;
        final totalLikes = await row.total_likes;
        print('    $name: $postCount posts, $totalLikes total likes');
      }
    }

    // ──────────────────────────────────────────────────
    //  Step 8: Clean up
    // ──────────────────────────────────────────────────
    print('\nStep 8: Closing database...');
    await db.close();
    print('  ✓ Database closed');

    print('\n══════════════════════════════════════════════════════');
    print(' SQLite CRUD — better-sqlite3 from Dart, zero JS!');
    print('══════════════════════════════════════════════════════');
  } finally {
    await js.dispose();
  }
}
