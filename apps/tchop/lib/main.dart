import 'bootstrap.dart';
import 'core/flavor.dart';

/// Default entrypoint. Used by iOS schemes via `--dart-define=FLAVOR=<flavor>`
/// and as a fallback for `flutter run` without an explicit `-t` target.
Future<void> main() => bootstrap(resolveFlavor());
