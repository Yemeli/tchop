import 'tchop_database.dart';

/// Stub — never used directly. The conditional import below picks the real
/// implementation per platform.
TchopDatabase openDatabaseConnection() =>
    throw UnsupportedError('No database implementation for this platform');
