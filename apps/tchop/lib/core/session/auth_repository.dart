import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_client.dart';

/// Server calls for authentication, memberships and workspace provisioning.
///
/// All French-facing errors surface as [AuthFailure] with a ready-to-show
/// message. Throws [StateError] when the backend is not configured — callers
/// (screens) translate that into the offline/demo UI.
class AuthRepository {
  AuthRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _client =>
      _clientOverride ?? TchopSupabase.clientOrNull;

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError(
        'Backend non configuré. Connectez-vous à Internet et configurez '
        'Supabase pour utiliser la connexion par SMS.',
      );
    }
    return client;
  }

  // ------------------------------------------------------------------
  // Phone OTP (MTN / Orange SMS via Supabase Auth)
  // ------------------------------------------------------------------

  /// Sends the 6-digit SMS code to [e164phone] (`+2376XXXXXXXX`).
  Future<void> requestOtp(String e164phone) async {
    try {
      await _requireClient().auth.signInWithOtp(phone: e164phone);
    } on AuthException catch (e) {
      throw AuthFailure(_friendlyAuthError(e.message));
    } catch (_) {
      throw AuthFailure(
        'Impossible d’envoyer le SMS. Vérifiez votre connexion et réessayez.',
      );
    }
  }

  /// Verifies the code the user typed. On success Supabase persists the
  /// session and fires `onAuthStateChange` (SIGNED_IN).
  Future<void> verifyOtp({
    required String phone,
    required String token,
  }) async {
    try {
      await _requireClient().auth.verifyOTP(
            phone: phone,
            token: token,
            type: OtpType.sms,
          );
    } on AuthException catch (e) {
      throw AuthFailure(_friendlyAuthError(e.message));
    } catch (_) {
      throw AuthFailure(
        'La vérification a échoué. Vérifiez votre connexion et réessayez.',
      );
    }
  }

  Future<void> signOut() async {
    final client = _client;
    if (client == null) return;
    try {
      await client.auth.signOut();
    } catch (_) {
      // Signing out is best-effort: the local session is cleared below
      // by SessionContext regardless.
    }
  }

  // ------------------------------------------------------------------
  // Memberships
  // ------------------------------------------------------------------

  /// The signed-in user's memberships, joined with tenant names.
  /// RLS (`users read own memberships`) guarantees tenant isolation.
  Future<List<Map<String, dynamic>>> fetchMemberships() async {
    final rows = await _requireClient()
        .from('memberships')
        .select('id, tenant_id, role, invited_phone, tenants(id, name)')
        .order('created_at');
    return (rows as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  /// Links pending invites (`invited_phone` matches the user's auth phone)
  /// to this user. Best-effort: returns the number claimed, 0 on any error.
  Future<int> claimInvites() async {
    final client = _client;
    if (client == null) return 0;
    try {
      final result = await client.rpc('claim_invited_memberships');
      return (result as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ------------------------------------------------------------------
  // Workspace provisioning (online only — slug uniqueness is server-side)
  // ------------------------------------------------------------------

  /// Live availability check for a workspace slug.
  Future<bool> slugAvailable(String slug) async {
    final result = await _requireClient()
        .rpc('slug_available', params: {'p_slug': slug});
    return (result as bool?) ?? false;
  }

  /// Atomically creates tenant + owner membership + 30-day trial
  /// subscription via the `create_workspace` SECURITY DEFINER function.
  /// Returns the created tenant row.
  Future<Map<String, dynamic>> createWorkspace({
    required String name,
    required String slug,
    String? primaryColor,
    String? secondaryColor,
    String? logoUrl,
  }) async {
    try {
      final result = await _requireClient().rpc(
        'create_workspace',
        params: {
          'p_name': name,
          'p_slug': slug,
          'p_primary_color': primaryColor,
          'p_secondary_color': secondaryColor,
          'p_logo_url': logoUrl,
        },
      );
      if (result is List && result.isNotEmpty) {
        return (result.first as Map).cast<String, dynamic>();
      }
      if (result is Map) return result.cast<String, dynamic>();
      throw const AuthFailure('Réponse inattendue du serveur.');
    } on PostgrestException catch (e) {
      if (e.message.contains('slug_taken')) {
        throw const AuthFailure(
          'Ce nom court est déjà pris. Essayez-en un autre.',
        );
      }
      if (e.message.contains('invalid_slug')) {
        throw const AuthFailure(
          'Nom court invalide : lettres minuscules, chiffres et tirets uniquement.',
        );
      }
      if (e.message.contains('not_authenticated')) {
        throw const AuthFailure(
          'Votre session a expiré. Reconnectez-vous et réessayez.',
        );
      }
      throw AuthFailure('La création a échoué : ${e.message}');
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(
        'Aucune connexion Internet. Reconnectez-vous et réessayez.',
      );
    }
  }

  /// Uploads the restaurant logo to `brand/{tenantId}/logo.png` and returns
  /// its public URL.
  Future<String> uploadLogo({
    required String tenantId,
    required XFile file,
  }) async {
    final client = _requireClient();
    final path = '$tenantId/logo.png';
    try {
      await client.storage.from('brand').upload(
            path,
            File(file.path),
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/png',
            ),
          );
      return client.storage.from('brand').getPublicUrl(path);
    } on StorageException catch (e) {
      throw AuthFailure('Le logo n’a pas pu être téléversé : ${e.message}');
    } catch (_) {
      throw const AuthFailure(
        'Le logo n’a pas pu être téléversé. Vérifiez votre connexion.',
      );
    }
  }

  // ------------------------------------------------------------------

  String _friendlyAuthError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid') && lower.contains('otp')) {
      return 'Code incorrect. Vérifiez le SMS et réessayez.';
    }
    if (lower.contains('expired')) {
      return 'Ce code a expiré. Demandez un nouveau code.';
    }
    if (lower.contains('rate limit') || lower.contains('too many')) {
      return 'Trop de tentatives. Patientez quelques minutes avant de réessayer.';
    }
    if (lower.contains('phone')) {
      return 'Numéro invalide. Utilisez le format +237 6 XX XX XX XX.';
    }
    return 'La connexion a échoué : $message';
  }
}

/// User-facing, French-localized error from the auth / provisioning layer.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
