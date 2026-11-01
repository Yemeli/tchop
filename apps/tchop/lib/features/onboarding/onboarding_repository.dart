import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/session/auth_repository.dart';

/// Orchestrates workspace creation: the atomic server-side
/// `create_workspace` RPC (tenant + owner membership + 30-day trial), then
/// the logo upload to `brand/{tenantId}/logo.png`.
///
/// Workspace creation itself REQUIRES connectivity (slug uniqueness is
/// server-side) — the repository throws [AuthFailure] with a French
/// message when offline. The logo step is graceful: it can be skipped, and
/// a failed upload is queued in a small on-device pending file and retried
/// later. Callers persist an uploaded logo URL through the offline-capable
/// outbox op `branding/update` (via `SessionContext.enqueueMutation`).
class OnboardingRepository {
  OnboardingRepository({AuthRepository? auth})
      : _auth = auth ?? AuthRepository();

  final AuthRepository _auth;

  /// Creates the workspace and returns the new tenant id plus the logo
  /// outcome. Partial failure cannot corrupt data: the RPC is a single
  /// transaction, so either tenant + membership + subscription all exist
  /// or nothing does.
  Future<WorkspaceCreationResult> createWorkspace({
    required String name,
    required String slug,
    String? primaryColor,
    String? secondaryColor,
    XFile? logoFile,
  }) async {
    final row = await _auth.createWorkspace(
      name: name,
      slug: slug,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
    );
    final tenantId = row['id'] as String;

    String? logoUrl;
    var logoPending = false;
    if (logoFile != null) {
      try {
        logoUrl = await _auth.uploadLogo(tenantId: tenantId, file: logoFile);
      } catch (_) {
        // Workspace exists; the logo will be retried later.
        await queuePendingLogo(tenantId, logoFile.path);
        logoPending = true;
      }
    }
    return WorkspaceCreationResult(
      tenantId: tenantId,
      logoUrl: logoUrl,
      logoPending: logoPending,
    );
  }

  // ------------------------------------------------------------------
  // Pending logo uploads (graceful offline)
  // ------------------------------------------------------------------

  Future<File> _pendingFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/tchop_pending_logos.json');
  }

  Future<Map<String, String>> _readPending() async {
    try {
      final file = await _pendingFile();
      if (!await file.exists()) return {};
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return {};
      return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  /// Queues a logo upload that failed (e.g. connection dropped after the
  /// workspace was created).
  Future<void> queuePendingLogo(String tenantId, String localPath) async {
    final pending = await _readPending();
    pending[tenantId] = localPath;
    await (await _pendingFile()).writeAsString(jsonEncode(pending));
  }

  Future<String?> pendingLogoPath(String tenantId) async =>
      (await _readPending())[tenantId];

  /// Retries every queued logo upload.
  /// Returns `{tenantId: publicUrl}` for the uploads that succeeded; the
  /// caller persists each URL via the `branding/update` outbox op.
  Future<Map<String, String>> retryPendingLogos() async {
    final pending = await _readPending();
    final succeeded = <String, String>{};
    if (pending.isEmpty) return succeeded;
    final remaining = Map<String, String>.from(pending);
    for (final entry in pending.entries) {
      final local = File(entry.value);
      if (!await local.exists()) {
        remaining.remove(entry.key);
        continue;
      }
      try {
        final url = await _auth.uploadLogo(
          tenantId: entry.key,
          file: XFile(entry.value),
        );
        remaining.remove(entry.key);
        succeeded[entry.key] = url;
      } catch (_) {
        // keep queued for the next attempt
      }
    }
    await (await _pendingFile()).writeAsString(jsonEncode(remaining));
    return succeeded;
  }
}

/// Outcome of [OnboardingRepository.createWorkspace].
class WorkspaceCreationResult {
  const WorkspaceCreationResult({
    required this.tenantId,
    required this.logoUrl,
    required this.logoPending,
  });

  final String tenantId;

  /// Public URL of the uploaded logo, null when skipped or still pending.
  final String? logoUrl;

  bool get logoUploaded => logoUrl != null;

  /// A logo was picked but the upload failed; it is queued for retry.
  final bool logoPending;
}
