import 'bootstrap.dart';
import 'core/flavor.dart';

/// Manager / secretary dashboard entrypoint (web + mobile).
/// Build: `flutter run --flavor manager -t lib/main_manager.dart`
Future<void> main() => bootstrap(AppFlavor.manager);
