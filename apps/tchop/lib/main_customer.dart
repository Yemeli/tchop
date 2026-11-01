import 'bootstrap.dart';
import 'core/flavor.dart';

/// Customer storefront entrypoint.
/// Build: `flutter run --flavor customer -t lib/main_customer.dart`
Future<void> main() => bootstrap(AppFlavor.customer);
