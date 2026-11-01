// Platform-split database opener.
//
// - Mobile/desktop (dart:io): native SQLite via drift/native.dart
// - Web: sql.js via drift/web.dart (dart:ffi is unavailable on web)
//
// Import this file everywhere; the conditional export picks the right
// implementation at compile time so `dart:io` never leaks into web builds.
export 'database_connection_stub.dart'
    if (dart.library.io) 'database_connection_native.dart'
    if (dart.library.html) 'database_connection_web.dart';
