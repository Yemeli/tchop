import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/database/tchop_database.dart';
import '../../data/supabase_client.dart';
import '../../data/sync/sync_engine.dart';
import '../branding/tenant_branding_controller.dart';
import 'auth_repository.dart';
import 'workspace_membership.dart';

/// Canonical session contract for Project Tchop — every feature reads the
/// signed-in user, the active workspace and the active role from here.
///
/// Lifecycle:
///   1. `bootstrap()` builds it and awaits [init()];
///   2. [init] restores the Supabase session (persisted on-device by
///      supabase_flutter, readable even offline), claims pending invites,
///      loads memberships (server → Drift cache), and auto-selects the
///      workspace when the user belongs to exactly one;
///   3. widgets read it via [SessionScope] and rebuild on [notifyListeners];
///   4. [switchTenant] changes the active workspace and re-themes the app via
///      [TenantBrandingController.switchToWorkspace].
///
/// Route-guard rules (see `SessionGate` in app.dart):
/// unauthenticated → sign-in · signed in with no workspace → onboarding ·
/// signed in with several workspaces and none active → workspace picker.
///
/// NOTE (Feature 3 / Menu studio): this file replaces the earlier stub.
/// `switchTenant` and `signOut` are now async (`Future<void>`) — existing
/// call sites that ignore the return value still compile; add `await` where
/// ordering matters. `userId`/`tenantId`/`role`/`workspaces` are now
/// read-only getters; mutate through [switchTenant]/[signOut]/[init].
class SessionContext extends ChangeNotifier {
  SessionContext({
    TenantBrandingController? branding,
    TchopDatabase? db,
    AuthRepository? authRepository,
    SyncEngine? syncEngine,
  })  : _branding = branding,
        _db = db,
        _auth = authRepository ?? AuthRepository(),
        _syncEngine = syncEngine;

  final TenantBrandingController? _branding;
  final TchopDatabase? _db;
  final AuthRepository _auth;
  final SyncEngine? _syncEngine;

  String? _userId;
  String? _phone;
  List<WorkspaceMembership> _memberships = const [];
  String? _tenantId;
  bool _loading = true;
  bool _demoMode = false;
  String? _lastError;
  StreamSubscription<AuthState>? _authSubscription;
  bool _disposed = false;

  // ------------------------------------------------------------------
  // Contract (other features rely on these)
  // ------------------------------------------------------------------

  /// Supabase auth user id, null when signed out.
  String? get userId => _userId;

  /// Active workspace (tenant) id, null when none is selected.
  String? get tenantId => _tenantId;

  /// Active role: owner|manager|head_chef|secretary|kitchen|driver.
  String? get role => _active?.role;

  /// `[{id, name, role}]` — every workspace the user belongs to.
  List<Map<String, String>> get workspaces =>
      _memberships.map((m) => m.toWorkspacesEntry()).toList();

  /// Raw memberships (for screens that need ids, e.g. the switcher).
  List<WorkspaceMembership> get memberships =>
      List.unmodifiable(_memberships);

  bool get isSignedIn => _userId != null || _demoMode;

  /// True while the initial session restore is running.
  bool get isLoading => _loading;

  /// Last non-fatal error (shown as a banner, never thrown at the gate).
  String? get lastError => _lastError;

  /// Authenticated phone in E.164, if known.
  String? get phone => _phone;

  /// True in offline demo mode (backend unconfigured).
  bool get isDemoMode => _demoMode;

  /// Only owners and managers may invite staff / edit branding.
  bool get canManageStaff => role == 'owner' || role == 'manager';

  /// Only the owner may touch ownership-level settings.
  bool get isOwner => role == 'owner';

  WorkspaceMembership? get _active {
    final id = _tenantId;
    if (id == null) return null;
    for (final m in _memberships) {
      if (m.tenantId == id) return m;
    }
    return null;
  }

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  /// Restores the session. Safe to call once from `bootstrap()`.
  Future<void> init() async {
    _setLoading(true);
    try {
      final client = TchopSupabase.clientOrNull;
      if (client == null) {
        // Backend unconfigured: stay signed out; the sign-in screen offers
        // the offline demo instead.
        return;
      }
      await _authSubscription?.cancel();
      _authSubscription =
          client.auth.onAuthStateChange.listen(_onAuthStateChange);
      final session = client.auth.currentSession;
      if (session != null) {
        // currentSession is read from on-device storage, so this also
        // restores the workspace after an offline restart.
        await _loadAuthenticatedSession(session.user);
      } else {
        await _loadCachedMemberships();
      }
    } catch (e) {
      _lastError = 'Session : $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _onAuthStateChange(AuthState state) async {
    switch (state.event) {
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.userUpdated:
        final user = state.session?.user;
        if (user != null) {
          await _loadAuthenticatedSession(user);
        }
      case AuthChangeEvent.signedOut:
      case AuthChangeEvent.userDeleted:
        await _clearLocalSession();
      case AuthChangeEvent.initialSession:
        break; // handled by init()
      case AuthChangeEvent.passwordRecovery:
      case AuthChangeEvent.mfaChallengeVerified:
        break;
    }
  }

  /// Reloads memberships from the server — called after OTP verification
  /// and after workspace creation so the gate reacts immediately even if
  /// the auth-state event is still in flight.
  Future<void> refreshMemberships() async {
    final client = TchopSupabase.clientOrNull;
    final user = client?.auth.currentUser;
    if (user == null) return;
    await _loadAuthenticatedSession(user);
  }

  Future<void> _loadAuthenticatedSession(User user) async {
    _userId = user.id;
    _phone = user.phone;
    _demoMode = false;
    try {
      // Link invites created via `membership/invite` before reading.
      await _auth.claimInvites();
      final rows = await _auth.fetchMemberships();
      _memberships = rows.map(WorkspaceMembership.fromSupabaseRow).toList();
      await _cacheMemberships();
      _lastError = null;
    } catch (e) {
      // Offline with a valid session: fall back to the Drift cache so the
      // workspace (and its brand) still loads.
      _lastError =
          'Hors-ligne : affichage des restaurants enregistrés sur cet appareil.';
      await _loadCachedMemberships();
    }
    await _resolveActiveTenant();
    _notify();
  }

  /// Picks the active workspace: previously-active (cached flag) wins,
  /// otherwise exactly-one membership auto-selects, otherwise none (the
  /// gate shows the picker / onboarding).
  Future<void> _resolveActiveTenant() async {
    String? active;
    if (_db != null && _userId != null) {
      final cached = await _db.activeMembership(_userId!);
      if (cached != null &&
          _memberships.any((m) => m.tenantId == cached.tenantId)) {
        active = cached.tenantId;
      }
    }
    active ??= pickDefaultWorkspaceId(_memberships);
    if (active != _tenantId) {
      _tenantId = active;
      if (active != null) {
        await _db?.setActiveMembership(active, userId: _userId);
        await _branding?.switchToWorkspace(active);
      }
    } else if (active != null) {
      // Same tenant but memberships refreshed — still refresh the brand.
      await _branding?.switchToWorkspace(active);
    }
  }

  Future<void> _cacheMemberships() async {
    final db = _db;
    final userId = _userId;
    if (db == null || userId == null) return;
    for (final m in _memberships) {
      await db.upsertMembership(
        MembershipsCompanion.insert(
          id: m.id,
          tenantId: m.tenantId,
          userId: userId,
          role: m.role,
          tenantName: Value(m.tenantName),
        ),
      );
    }
  }

  Future<void> _loadCachedMemberships() async {
    final db = _db;
    if (db == null) return;
    // Without a live session we cannot scope by user; the cache is only
    // ever written for the last signed-in user on this device.
    final rows = await db.allMemberships();
    _memberships = rows
        .map(
          (r) => WorkspaceMembership(
            id: r.id,
            tenantId: r.tenantId,
            tenantName: r.tenantName.isEmpty ? 'Restaurant' : r.tenantName,
            role: r.role,
          ),
        )
        .toList();
    final active = rows.where((r) => r.isActive).toList();
    _tenantId = active.isEmpty
        ? pickDefaultWorkspaceId(_memberships)
        : active.first.tenantId;
    if (_tenantId != null) {
      await _branding?.switchToWorkspace(_tenantId!);
    }
  }

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  /// Switches the active workspace: reloads memberships, persists the
  /// choice, and re-themes the app via the branding controller.
  Future<void> switchTenant(String tenantId) async {
    if (!_memberships.any((m) => m.tenantId == tenantId)) {
      throw StateError('Restaurant inconnu sur cet appareil.');
    }
    // Best-effort refresh so a role change propagates immediately.
    try {
      final rows = await _auth.fetchMemberships();
      _memberships = rows.map(WorkspaceMembership.fromSupabaseRow).toList();
      await _cacheMemberships();
    } catch (_) {
      // keep the cached list; the switch still works offline
    }
    _tenantId = tenantId;
    await _db?.setActiveMembership(tenantId, userId: _userId);
    _notify();
    await _branding?.switchToWorkspace(tenantId);
  }

  /// Signs out everywhere: Supabase session, local flags, active workspace.
  Future<void> signOut() async {
    await _auth.signOut();
    await _clearLocalSession();
  }

  Future<void> _clearLocalSession() async {
    await _db?.clearActiveMemberships();
    _userId = null;
    _phone = null;
    _memberships = const [];
    _tenantId = null;
    _demoMode = false;
    _lastError = null;
    _notify();
  }

  /// Offline demo entry point (backend unconfigured). No user, no
  /// workspace — the gate sends demo users straight home with the sample
  /// brand loaded by `bootstrap()`.
  Future<void> signInDemo() async {
    _demoMode = true;
    _userId = null;
    _memberships = const [];
    _tenantId = null;
    _notify();
  }

  /// Backwards-compatible demo stand-in (Feature 3 stub API).
  factory SessionContext.demo() {
    final ctx = SessionContext();
    ctx._demoMode = true;
    ctx._userId = 'demo-user';
    ctx._tenantId = 'demo-tenant';
    ctx._memberships = const [
      WorkspaceMembership(
        id: 'demo-membership',
        tenantId: 'demo-tenant',
        tenantName: 'Restaurant Démo',
        role: 'manager',
      ),
    ];
    return ctx;
  }

  /// Enqueues an offline-capable mutation (invite, branding, …) and
  /// best-effort drains it right away when online.
  Future<String> enqueueMutation({
    required String tenantId,
    required String op,
    required String entity,
    required String entityId,
    required Map<String, Object?> payload,
    String? clientMutationId,
  }) async {
    final engine = _syncEngine;
    if (engine == null) {
      throw StateError('Moteur de synchronisation indisponible.');
    }
    final id = await engine.enqueue(
      tenantId: tenantId,
      op: op,
      entity: entity,
      entityId: entityId,
      payload: payload,
      clientMutationId: clientMutationId,
    );
    unawaited(engine.drain());
    return id;
  }

  // ------------------------------------------------------------------

  void _setLoading(bool value) {
    _loading = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _authSubscription?.cancel();
    super.dispose();
  }
}

/// Exposes the [SessionContext] to the widget tree (sibling to
/// [TenantBrandingScope]).
class SessionScope extends InheritedNotifier<SessionContext> {
  const SessionScope({
    super.key,
    required SessionContext session,
    required super.child,
  }) : super(notifier: session);

  static SessionContext? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()?.notifier;

  static SessionContext of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<SessionScope>()
        : context.getElementForInheritedWidgetOfExactType<SessionScope>()
            ?.widget as SessionScope?;
    assert(scope != null, 'SessionScope not found in widget tree');
    return scope!.notifier!;
  }
}
