import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../data/supabase_client.dart';
import '../../data/sync/sync_engine.dart';

/// Stored payment credential row (masked — plaintext never reaches the
/// device from the server, and the device never persists plaintext).
class PaymentCredential {
  const PaymentCredential({
    required this.id,
    required this.provider,
    required this.label,
    required this.keyFingerprint,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String provider;
  final String label;
  final String keyFingerprint;
  final bool isActive;
  final DateTime createdAt;

  factory PaymentCredential.fromJson(Map<String, dynamic> json) =>
      PaymentCredential(
        id: json['id'] as String,
        provider: json['provider'] as String,
        label: json['label'] as String,
        keyFingerprint: json['key_fingerprint'] as String,
        isActive: (json['is_active'] as bool?) ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Result of the "Tester la connexion" sandbox check.
class CredentialVerifyResult {
  const CredentialVerifyResult({
    required this.verified,
    required this.demo,
    this.reason,
    this.detail,
  });

  /// True only when a provider sandbox really accepted the credential.
  final bool verified;

  /// True when the check could not reach a sandbox — the UI MUST label
  /// this "Mode démo — vérification simulée" and never as a success.
  final bool demo;

  /// Machine reason, e.g. "sandbox_indisponible", "sandbox_refuse".
  final String? reason;

  /// Human-readable detail (French) when the server provides one.
  final String? detail;

  factory CredentialVerifyResult.fromJson(Map<String, dynamic> json) =>
      CredentialVerifyResult(
        verified: (json['verified'] as bool?) ?? false,
        demo: (json['demo'] as bool?) ?? true,
        reason: json['reason'] as String?,
        detail: json['detail'] as String?,
      );

  /// Honest fallback when the edge function cannot be reached at all.
  factory CredentialVerifyResult.unreachable() =>
      const CredentialVerifyResult(
        verified: false,
        demo: true,
        reason: 'sandbox_indisponible',
      );
}

/// A recorded end-of-day cash reconciliation.
class CashClose {
  const CashClose({
    required this.id,
    required this.businessDate,
    required this.expected,
    required this.counted,
    required this.variance,
    required this.createdAt,
  });

  final String id;
  final DateTime businessDate;
  final int expected;
  final int counted;
  final int variance;
  final DateTime createdAt;

  factory CashClose.fromJson(Map<String, dynamic> json) => CashClose(
        id: json['id'] as String,
        businessDate: DateTime.parse(json['business_date'] as String),
        expected: (json['expected'] as num).toInt(),
        counted: (json['counted'] as num).toInt(),
        variance: (json['variance'] as num).toInt(),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// A refund request in the four-eyes workflow.
class RefundRequest {
  const RefundRequest({
    required this.id,
    required this.paymentId,
    required this.orderId,
    required this.amount,
    required this.reason,
    required this.status,
    required this.requestedBy,
    required this.requestedAt,
  });

  final String id;
  final String paymentId;
  final String? orderId;
  final int amount;
  final String reason;
  final String status;
  final String? requestedBy;
  final DateTime requestedAt;

  factory RefundRequest.fromJson(Map<String, dynamic> json) => RefundRequest(
        id: json['id'] as String,
        paymentId: json['payment_id'] as String,
        orderId: json['order_id'] as String?,
        amount: (json['amount'] as num).toInt(),
        reason: json['reason'] as String,
        status: json['status'] as String,
        requestedBy: json['requested_by'] as String?,
        requestedAt: DateTime.parse(json['requested_at'] as String),
      );
}

/// Payments data access.
///
/// Write path (mirrors OrderRepository): every mutation goes through
/// [SyncEngine.enqueue] so it works offline; reads go to Supabase when
/// online. Credential VALUES are never written to the local Drift DB —
/// they live in TextEditingControllers (device memory) only until the
/// outbox op is acknowledged, and the controllers are cleared right after.
class PaymentRepository {
  PaymentRepository({
    required SyncEngine syncEngine,
    Uuid? uuids,
  })  : _sync = syncEngine,
        _uuids = uuids ?? const Uuid();

  final SyncEngine _sync;
  final Uuid _uuids;

  /// Best-effort drain after a mutation (fire-and-forget; the engine also
  /// drains on every reconnect). Swallows offline errors — the outbox keeps
  /// the intent.
  Future<void> syncNow() async {
    try {
      await _sync.drain();
    } catch (_) {
      // Offline: the outbox entry persists and syncs on reconnect.
    }
  }

  // ------------------------------------------------------------------
  // Credential lifecycle (owner/manager only — enforced server-side too)
  // ------------------------------------------------------------------

  /// Saves a new credential blob. [fields] is the provider field map
  /// (e.g. {"api_user": "…", "api_key": "…"}); it is JSON-encoded into the
  /// outbox payload and encrypted server-side via Supabase Vault.
  Future<void> saveCredentials({
    required String tenantId,
    required String provider,
    required String label,
    required Map<String, String> fields,
  }) =>
      _sync.enqueue(
        tenantId: tenantId,
        op: 'payments/credentials_save',
        entity: 'payment_credential',
        entityId: _uuids.v4(),
        payload: {
          'provider': provider,
          'label': label,
          'secret': jsonEncode(fields),
        },
      );

  /// Rotates an existing credential (new Vault secret, pointer swapped).
  Future<void> rotateCredentials({
    required String tenantId,
    required String credentialId,
    required Map<String, String> fields,
  }) =>
      _sync.enqueue(
        tenantId: tenantId,
        op: 'payments/credentials_rotate',
        entity: 'payment_credential',
        entityId: credentialId,
        payload: {'secret': jsonEncode(fields)},
      );

  /// Revokes a credential (is_active=false; audit trail kept).
  Future<void> revokeCredentials({
    required String tenantId,
    required String credentialId,
  }) =>
      _sync.enqueue(
        tenantId: tenantId,
        op: 'payments/credentials_revoke',
        entity: 'payment_credential',
        entityId: credentialId,
        payload: const {},
      );

  /// Connected accounts for this tenant (masked fingerprints only).
  Future<List<PaymentCredential>> listCredentials(String tenantId) async {
    final client = TchopSupabase.clientOrNull;
    if (client == null) return const [];
    final rows = await client
        .from('tenant_payment_credentials')
        .select('id, provider, label, key_fingerprint, is_active, created_at')
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false);
    return [
      for (final row in (rows as List).cast<Map<String, dynamic>>())
        PaymentCredential.fromJson(row),
    ];
  }

  /// "Tester la connexion": interactive sandbox check via the
  /// `payments-verify` edge function. Never fakes a success — an
  /// unreachable sandbox returns an honest demo result.
  Future<CredentialVerifyResult> verifyConnection({
    required String tenantId,
    required String credentialId,
  }) async {
    final client = TchopSupabase.clientOrNull;
    if (client == null) return CredentialVerifyResult.unreachable();
    try {
      final res = await client.functions.invoke(
        'payments-verify',
        body: {'tenant_id': tenantId, 'credential_id': credentialId},
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        return CredentialVerifyResult.fromJson(data);
      }
      return CredentialVerifyResult.unreachable();
    } catch (_) {
      return CredentialVerifyResult.unreachable();
    }
  }

  // ------------------------------------------------------------------
  // Cash reconciliation (secretary / owner / manager)
  // ------------------------------------------------------------------

  /// Expected cash for today: sum of delivered cash orders since local
  /// midnight (device is in the restaurant's timezone). Indicative — the
  /// server-side close recomputes variance from the submitted numbers.
  Future<int> expectedCashToday(String tenantId) async {
    final client = TchopSupabase.clientOrNull;
    if (client == null) return 0;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    try {
      final rows = await client
          .from('orders')
          .select('total')
          .eq('tenant_id', tenantId)
          .eq('payment_method', 'cash')
          .eq('status', 'delivered')
          .gte('created_at', startOfDay.toUtc().toIso8601String());
      var sum = 0;
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        sum += (row['total'] as num?)?.toInt() ?? 0;
      }
      return sum;
    } catch (_) {
      return 0;
    }
  }

  /// Closes the cash day: variance is recomputed server-side.
  Future<void> closeCashDay({
    required String tenantId,
    required DateTime businessDate,
    required int expected,
    required int counted,
    String? note,
  }) =>
      _sync.enqueue(
        tenantId: tenantId,
        op: 'payments/cash_close',
        entity: 'cash_close',
        entityId: _uuids.v4(),
        payload: {
          'business_date': businessDate.toIso8601String().substring(0, 10),
          'expected': expected,
          'counted': counted,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );

  /// Past closes, newest first.
  Future<List<CashClose>> cashCloseHistory(String tenantId) async {
    final client = TchopSupabase.clientOrNull;
    if (client == null) return const [];
    final rows = await client
        .from('cash_closes')
        .select('id, business_date, expected, counted, variance, created_at')
        .eq('tenant_id', tenantId)
        .order('business_date', ascending: false);
    return [
      for (final row in (rows as List).cast<Map<String, dynamic>>())
        CashClose.fromJson(row),
    ];
  }

  /// The latest succeeded `payments` row id for an order (used by the order
  /// detail "Rembourser" button). Null when there is nothing to refund.
  Future<String?> succeededPaymentIdForOrder(String orderId) async {
    final client = TchopSupabase.clientOrNull;
    if (client == null) return null;
    try {
      final row = await client
          .from('payments')
          .select('id')
          .eq('order_id', orderId)
          .eq('status', 'succeeded')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row?['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------
  // Refunds (four-eyes: requester ≠ approver, enforced server-side)
  // ------------------------------------------------------------------

  /// Step 1 — owner/manager files a refund request for a succeeded payment.
  Future<void> requestRefund({
    required String tenantId,
    required String paymentId,
    required String reason,
  }) =>
      _sync.enqueue(
        tenantId: tenantId,
        op: 'payments/refund_request',
        entity: 'refund_request',
        entityId: _uuids.v4(),
        payload: {'payment_id': paymentId, 'reason': reason},
      );

  /// Pending requests awaiting a second pair of eyes.
  Future<List<RefundRequest>> pendingRefunds(String tenantId) async {
    final client = TchopSupabase.clientOrNull;
    if (client == null) return const [];
    final rows = await client
        .from('refund_requests')
        .select(
            'id, payment_id, order_id, amount, reason, status, requested_by, requested_at')
        .eq('tenant_id', tenantId)
        .eq('status', 'pending')
        .order('requested_at', ascending: true);
    return [
      for (final row in (rows as List).cast<Map<String, dynamic>>())
        RefundRequest.fromJson(row),
    ];
  }

  /// Step 2 — a *different* owner/manager approves or rejects. Approving
  /// marks the payment refunded in our books; the actual money-back is a
  /// MANUAL step in the provider's own app (MoMo has no public refund API
  /// for collections) — the UI says so explicitly.
  Future<void> decideRefund({
    required String tenantId,
    required String refundId,
    required bool approve,
    String? note,
  }) =>
      _sync.enqueue(
        tenantId: tenantId,
        op: approve ? 'payments/refund_approve' : 'payments/refund_reject',
        entity: 'refund_request',
        entityId: refundId,
        payload: {if (note != null && note.isNotEmpty) 'note': note},
      );
}
