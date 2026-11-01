import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/branding/tenant_brand_repository.dart';
import 'sample_brands.dart';
import 'tenant_brand.dart';

/// Single source of truth for the active workspace's brand.
///
/// Load flow (production): [switchToWorkspace] fetches `GET /tenant` after
/// auth/workspace selection — the backend returns the tenant row, we parse
/// it, cache the JSON in Drift, and notify; every screen rebuilds with the
/// restaurant's own theme. Offline, the Drift cache (or bundled samples) is
/// used so the app always renders.
///
/// Load flow (demo): [loadSampleBrand] from `assets/tenant_sample.json`.
///
/// Switching workspaces re-fetches the brand and rebuilds — no app restart.
/// The [TenantBrandingScope] (InheritedNotifier) API is unchanged.
class TenantBrandingController extends ChangeNotifier {
  TenantBrandingController({TenantBrandRepository? repository})
      : _repository = repository,
        _brand = TenantBrand.fallback();

  final TenantBrandRepository? _repository;

  TenantBrand _brand;
  TenantBrand get brand => _brand;

  bool _loading = false;
  bool get loading => _loading;

  String? _lastError;

  /// Human-readable reason the last workspace load fell back to cache/demo.
  /// Null when the last load succeeded.
  String? get lastError => _lastError;

  Future<void> loadFromJson(Map<String, dynamic> json) async {
    _setLoading(true);
    try {
      // TODO: validate against a brand schema (ajv/json_schema on backend);
      // reject unknown keys so tenants can't inject layout-breaking values.
      _brand = TenantBrand.fromJson(json);
      _lastError = null;
    } finally {
      _setLoading(false);
    }
  }

  /// Demo bootstrap: loads the bundled sample workspace.
  /// TODO: delete once real workspace resolution lands in [bootstrap].
  Future<void> loadSampleBrand() async {
    final raw = await rootBundle.loadString('assets/tenant_sample.json');
    await loadFromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Production workspace switch: network → Drift cache → bundled sample.
  ///
  /// Never throws: on total failure the current brand is kept and
  /// [lastError] explains why.
  Future<void> switchToWorkspace(String tenantId) async {
    _setLoading(true);
    try {
      TenantBrand? next;
      if (_repository != null) {
        next = await _repository.loadWorkspace(tenantId);
      }
      next ??= _offlineFallback(tenantId);
      _brand = next;
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      _brand = _offlineFallback(tenantId);
    } finally {
      _setLoading(false);
    }
  }

  /// Backwards-compatible switch with an already-built brand (demo flows,
  /// workspace switcher). Prefer [switchToWorkspace] for backend-backed
  /// switching.
  Future<void> switchWorkspace(TenantBrand next) async {
    if (next.restaurantId == _brand.restaurantId) return;
    _setLoading(true);
    try {
      _brand = next;
      _lastError = null;
      // TODO: clear workspace-scoped caches (menu, orders) and re-sync.
    } finally {
      _setLoading(false);
    }
  }

  TenantBrand _offlineFallback(String tenantId) {
    for (final workspace in sampleWorkspaces) {
      if (workspace.restaurantId == tenantId) return workspace;
    }
    return TenantBrand.fallback();
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }
}
