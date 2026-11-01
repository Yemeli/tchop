import 'bootstrap.dart';
import 'core/flavor.dart';

/// Driver app entrypoint (deliveries, navigation, proof of delivery).
/// Build: `flutter run --flavor driver -t lib/main_driver.dart`
Future<void> main() => bootstrap(AppFlavor.driver);
