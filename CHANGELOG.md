## 2.0.1

- Shortened package description to meet pub.dev guidelines
- Fixed angle bracket lint warnings in CLI doc comments

## 2.0.0

- Added `createFunction()` API for creating JS functions without eval
- Added `getGlobal()` / `setGlobal()` for globalThis access
- Hybrid proxy approach — Dart callbacks passed directly to JS
- Promise-returning callback support
- `$new`, `$has`, `$typeof`, `$get`, `$set`, `$toJson`, `$keys` helper methods on JsObject
- Eliminated all eval usage from internal APIs
- 7 example files demonstrating Express, WebSocket, JWT, SQLite, lodash/ramda, dayjs/moment, zod/joi
- 14 comprehensive npm package test suites (338 tests)

## 1.0.0

- Initial release
- Node.js engine via stdio IPC
- Full npm package management (install, remove, update, list)
- Dynamic proxy objects with path chaining (`await obj.nested.method(args)`)
- Automatic JS reference tracking with finalizer-based cleanup
- Comprehensive error handling with typed exceptions
- `eval()` for raw JavaScript evaluation
- Works with any npm package (lodash, axios, moment, etc.)
