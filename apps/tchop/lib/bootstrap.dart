import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_config.dart';
import 'core/branding/tenant_branding_controller.dart';
import 'core/flavor.dart';
import 'core/services_scope.dart';
import 'core/session/session_context.dart';
import 'core/settings/app_settings.dart';
import 'core/ui/app_settings_scope.dart';
import 'core/ui/startup_jank.dart';
import 'data/branding/tenant_brand_repository.dart';
import 'data/database/database_connection.dart';
import 'data/supabase_client.dart';
import 'data/sync/sync_engine.dart';
import 'features/menu/availability_broadcaster.dart';
import 'features/menu/menu_repository.dart';
import 'features/orders/order_repository.dart';

/// Shared startup sequence for every flavor entrypoint.
///
/// 1. Ensures the Flutter binding.
/// 2. Loads [AppConfig] (runtime-pasted keys from secure storage, then
///    `--dart-define` build-time defaults) — BEFORE Supabase init so pasted
///    keys are picked up with no rebuild.
/// 3. Initializes Supabase (no-op when keys are absent in both layers —
///    the app then runs fully offline in demo mode).
/// 3. Opens the on-device Drift database (offline source of truth).
/// 4. Creates the per-workspace [TenantBrandingController] backed by the
///    brand repository (network → Drift cache → samples).
/// 5. Creates the [SessionContext] and restores the session: Supabase Auth
///    session → claim invites → memberships → auto-select single workspace
///    → brand switch. When the backend is unconfigured, the sample brand is
///    loaded for the offline demo instead.
/// 6. Starts the [SyncEngine] (idle when Supabase is unconfigured; pending
///    mutations keep their badges).
/// 7. Runs the flavored app behind the [SessionGate] route guard.
Future<void> bootstrap(AppFlavor flavor) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop window chrome (Windows / macOS / Linux only): a sensible
  // default size instead of the tiny OS default. Never blocks startup —
  // if the plugin is missing from a build, we just skip it.
  await _configureDesktopWindow();

  // Runtime-pasted platform keys first — no rebuild needed to change them.
  await AppConfig.current.load();
  await TchopSupabase.initialize();

  final db = openDatabaseConnection();
  final branding = TenantBrandingController(
    repository: TenantBrandRepository(db),
  );
  final syncEngine = SyncEngine(db: db);
  final session = SessionContext(
    branding: branding,
    db: db,
    syncEngine: syncEngine,
  );

  // The session must ALWAYS initialize: skipping it leaves `_loading`
  // true and the SessionGate stuck on the splash screen forever. init()
  // is a no-op (stays signed out) when the backend is unconfigured.
  await session.init();
  if (!TchopSupabase.isConfigured) {
    await branding.loadSampleBrand();
  }

  syncEngine.start();

  // Menu studio services (Feature 3): draft persistence + debounced outbox
  // sync + the 86 Realtime broadcaster. Additive wiring — other features can
  // extend ServicesScope rather than replace it.
  final menuRepository = MenuRepository(db: db, syncEngine: syncEngine);
  final availabilityBroadcaster =
      AvailabilityBroadcaster(db: db, syncEngine: syncEngine);

  // Orders feature (Feature 4): the single canonical repository instance —
  // its constructor attaches the edge-response hook used to surface
  // `order/create` 409 validation conflicts (last-writer-wins).
  final orderRepository = OrderRepository(db: db, syncEngine: syncEngine);

  // Device-level preferences (Feature 9): reduced-motion, lite mode,
  // customer onboarding flag. Loaded BEFORE the first frame so the
  // SessionGate's onboarding check reads the persisted value.
  final appSettings = AppSettingsController(AppSettingsStore(db));
  await appSettings.load();

  // Honest startup-jank heuristic → one-time lite-mode suggestion.
  // Never auto-enables anything; the user decides in Paramètres.
  StartupJankMeter.onComplete = (janky) {
    if (janky) unawaited(appSettings.suggestLiteMode());
  };
  StartupJankMeter.begin();

  runApp(
    // Rebuilds the whole tree on any settings toggle so every
    // `AppSettingsScope.of(context).value` read stays fresh without
    // per-screen listeners (toggles are rare; rebuilds are cheap).
    ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) => AppSettingsScope(
        settings: appSettings,
        child: ServicesScope(
          db: db,
          syncEngine: syncEngine,
          menuRepository: menuRepository,
          availabilityBroadcaster: availabilityBroadcaster,
          orderRepository: orderRepository,
          child: TchopApp(
            flavor: flavor,
            branding: branding,
            session: session,
            db: db,
            sync: syncEngine,
          ),
        ),
      ),
    ),
  );
}

/// Desktop-only window setup: default 1280×800, minimum 1024×640, centered.
///
/// Guarded by platform checks so mobile/web builds never touch the plugin,
/// and wrapped in try/catch so a build missing the plugin still starts.
Future<void> _configureDesktopWindow() async {
  if (kIsWeb) return;
  final platform = defaultTargetPlatform;
  if (platform != TargetPlatform.windows &&
      platform != TargetPlatform.macOS &&
      platform != TargetPlatform.linux) {
    return;
  }
  try {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1280, 800),
        minimumSize: Size(1024, 640),
        center: true,
        title: 'Tchop',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  } catch (_) {
    // Plugin unavailable — start anyway with the OS default window.
  }
}
