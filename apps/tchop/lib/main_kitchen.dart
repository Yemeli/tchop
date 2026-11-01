import 'bootstrap.dart';
import 'core/flavor.dart';

/// Kitchen display entrypoint (ticket board).
/// Build: `flutter run --flavor kitchen -t lib/main_kitchen.dart`
Future<void> main() => bootstrap(AppFlavor.kitchen);
