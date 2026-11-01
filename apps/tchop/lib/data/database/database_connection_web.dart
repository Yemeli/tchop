import 'package:drift/drift.dart';
import 'package:drift/web.dart';

import 'tchop_database.dart';

/// Web implementation: SQLite via sql.js backed by IndexedDB.
///
/// `dart:ffi` (and therefore `NativeDatabase`) is unavailable on web, so we
/// use Drift's web database instead. Same schema, same API — the rest of the
/// app is unchanged.
TchopDatabase openDatabaseConnection() {
  return TchopDatabase(
    LazyDatabase(() async {
      return WebDatabase('tchop');
    }),
  );
}
