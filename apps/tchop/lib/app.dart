import 'package:flutter/material.dart';

import 'core/branding/tenant_branding_controller.dart';
import 'core/branding/tenant_branding_scope.dart';
import 'core/app_scroll_behavior.dart';
import 'core/flavor.dart';
import 'core/session/session_context.dart';
import 'core/ui/app_settings_scope.dart';
import 'core/ui/mascot.dart';
import 'data/database/tchop_database.dart';
import 'data/sync/sync_engine.dart';
import 'design_system/tchop_colors.dart';
import 'design_system/tchop_theme.dart';
import 'design_system/tchop_typography.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/auth/workspace_picker_screen.dart';
import 'features/customer/first_run_onboarding.dart';
import 'features/onboarding/create_workspace_screen.dart';

/// Root widget shared by all flavors.
///
/// [SessionScope] (session) wraps [TenantBrandingScope] (brand): the
/// [MaterialApp] rebuilds when the workspace (or its brand) changes, and the
/// [SessionGate] below enforces the route guard:
///
///   loading → splash · unauthenticated → sign-in ·
///   signed in, no workspace → onboarding · signed in, several workspaces,
///   none active → workspace picker · otherwise → the flavor's home screen.
///
/// The device [AppSettingsScope] (wired in `bootstrap.dart`, above this
/// widget) is also listened to: toggling "Réduire les animations" swaps
/// the page transitions to instant via
/// `buildTchopTheme(reducedMotion: true)`.
class TchopApp extends StatelessWidget {
  const TchopApp({
    super.key,
    required this.flavor,
    required this.branding,
    required this.session,
    this.db,
    this.sync,
  });

  final AppFlavor flavor;
  final TenantBrandingController branding;
  final SessionContext session;

  /// Exposed for screens that need local queries (kept optional so the
  /// widget stays constructible in tests).
  final TchopDatabase? db;
  final SyncEngine? sync;

  @override
  Widget build(BuildContext context) {
    // Null in widget tests that build TchopApp without bootstrap's scope.
    final appSettings = AppSettingsScope.maybeOf(context);
    return SessionScope(
      session: session,
      child: TenantBrandingScope(
        branding: branding,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            branding,
            if (appSettings != null) appSettings,
          ]),
          builder: (context, _) {
            final scope = TenantBrandingScope.of(context);
            final reducedMotion =
                appSettings?.value.reducedMotion ?? false;
            return MaterialApp(
              title: '${scope.name} · ${flavor.appLabel}',
              debugShowCheckedModeBanner: false,
              // Mouse/trackpad drag scrolling on web + desktop.
              scrollBehavior: const TchopScrollBehavior(),
              // Text-scale safety: honor the OS font size, but clamp it so
              // huge accessibility sizes can't blow layouts apart on
              // desktop/web. 1.25x still reads comfortably.
              builder: (context, child) {
                final mq = MediaQuery.of(context);
                final clamped = mq.textScaler.clamp(
                  minScaleFactor: 0.85,
                  maxScaleFactor: 1.25,
                );
                return MediaQuery(
                  data: mq.copyWith(textScaler: clamped),
                  child: child ?? const SizedBox.shrink(),
                );
              },
              theme: buildTchopTheme(scope,
                  reducedMotion: reducedMotion),
              home: SessionGate(flavor: flavor),
            );
          },
        ),
      ),
    );
  }
}

/// Route guard driven by [SessionContext].
class SessionGate extends StatelessWidget {
  const SessionGate({super.key, required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.isLoading) return const _SplashScreen();
        if (!session.isSignedIn) return const SignInScreen();
        // Customer storefront: shoppers don't need a staff workspace; the
        // brand follows the auto-selected workspace when there is exactly one.
        if (flavor == AppFlavor.customer) {
          // First run → 3-page onboarding (Commander / Suivre / Payer),
          // shown once via the persisted flag. maybeOf is null only in
          // tests without bootstrap's scope — then skip straight in.
          final settings =
              AppSettingsScope.maybeOf(context);
          if (settings != null &&
              !settings.value.customerOnboardingSeen) {
            return const FirstRunOnboardingScreen();
          }
          return flavor.homeScreen;
        }
        if (session.tenantId == null) {
          // Signed in but no workspace: onboarding for first-timers,
          // picker when several memberships exist.
          return session.workspaces.isEmpty
              ? const CreateWorkspaceScreen()
              : const WorkspacePickerScreen();
        }
        return flavor.homeScreen;
      },
    );
  }
}

/// Branded launch splash: tenant brand + mascot slot + loading indicator.
///
/// The mascot plays `assets/rive/splash.riv` once brand artwork is
/// registered; until then it renders the drawn cloche fallback.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final brand = TenantBrandingScope.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MascotWidget(
              slot: MascotSlot.splash,
              size: 120,
              brandColor: brand.primary,
            ),
            const SizedBox(height: TchopSpacing.lg),
            Text(brand.name, style: TchopTypography.displayMedium),
            if (brand.tagline != null) ...[
              const SizedBox(height: TchopSpacing.xs),
              Text(brand.tagline!, style: TchopTypography.bodySmall),
            ],
            const SizedBox(height: TchopSpacing.xl),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: TchopSpacing.sm),
            const Text('Chargement…', style: TchopTypography.bodySmall),
          ],
        ),
      ),
    );
  }
}
