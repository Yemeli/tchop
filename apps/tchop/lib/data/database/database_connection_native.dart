import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tchop_database.dart';

/// Opens the on-device SQLite database — the source of truth when offline.
///
/// Runs queries on a background isolate so the UI thread never blocks on I/O
/// (important on the low-end Android devices common in our markets).
TchopDatabase openDatabaseConnection() {
  return TchopDatabase(
    LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      return NativeDatabase.createInBackground(
        File(p.join(dir.path, 'tchop.sqlite')),
      );
    }),
  );
}
