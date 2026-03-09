## 1.0.0

- Initial release
- Node.js engine via stdio IPC
- Full npm package management (install, remove, update, list)
- Dynamic proxy objects with path chaining (`await obj.nested.method(args)`)
- Automatic JS reference tracking with finalizer-based cleanup
- Comprehensive error handling with typed exceptions
- `eval()` for raw JavaScript evaluation
- Works with any npm package (lodash, axios, moment, etc.)
