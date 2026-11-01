import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../design_system/tchop_colors.dart';
import '../../core/services_scope.dart';
import '../../core/session/session_context.dart';
import '../../design_system/tchop_typography.dart';
import 'dispatch_repository.dart';
import 'signature_pad.dart';

/// Shows the proof-of-delivery sheet after the driver taps "Livrée".
///
/// Collects: a delivery photo (camera → Supabase Storage, offline-tolerant),
/// the customer's signature (hand-rolled [SignaturePad]) and a geotag.
/// Submits through [DispatchRepository.completeDelivery] — the single
/// `delivery/complete` outbox op.
Future<void> showProofOfDeliverySheet({
  required BuildContext context,
  required String deliveryId,
  required String orderId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ProofOfDeliverySheet(
      deliveryId: deliveryId,
      orderId: orderId,
    ),
  );
}

class _ProofOfDeliverySheet extends StatefulWidget {
  const _ProofOfDeliverySheet({
    required this.deliveryId,
    required this.orderId,
  });

  final String deliveryId;
  final String orderId;

  @override
  State<_ProofOfDeliverySheet> createState() => _ProofOfDeliverySheetState();
}

class _ProofOfDeliverySheetState extends State<_ProofOfDeliverySheet> {
  final _sigController = SignaturePadController();
  final _picker = ImagePicker();
  File? _photo;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _sigController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        imageQuality: 80,
      );
      if (shot == null) return;
      setState(() {
        _photo = File(shot.path);
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Photo impossible : $e');
    }
  }

  Future<Position?> _geotag() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return null; // geotag is best-effort; PoD stays valid without it
    }
  }

  Future<void> _submit() async {
    if (_photo == null) {
      setState(() => _error = 'Prenez une photo du colis remis.');
      return;
    }
    if (_sigController.isEmpty) {
      setState(() => _error = 'Faites signer le client.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final services = ServicesScope.of(context);
      final session = SessionScope.of(context, listen: false);
      final tenantId = session.tenantId;
      if (tenantId == null) throw StateError('Aucun restaurant actif.');
      final repo = DispatchRepository(
        db: services.db,
        syncEngine: services.syncEngine,
      );

      final pos = await _geotag();
      // Offline-tolerant upload: null → the local path is queued in the
      // payload as `pod_photo_pending_path` for a background retry.
      final photoUrl = _photo == null
          ? null
          : await repo.uploadPodPhoto(
              tenantId: tenantId,
              deliveryId: widget.deliveryId,
              photo: _photo!,
            );

      await repo.completeDelivery(
        tenantId: tenantId,
        deliveryId: widget.deliveryId,
        orderId: widget.orderId,
        podPhotoUrl: photoUrl,
        podPhotoPendingPath: photoUrl == null ? _photo?.path : null,
        podLat: pos?.latitude,
        podLng: pos?.longitude,
        signatureSvg: _sigController.toSvg(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _showDoneDialog(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Échec de l’envoi : $e';
        });
      }
    }
  }

  void _showDoneDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Livraison terminée ✓'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preuve de livraison enregistrée.'),
            SizedBox(height: 12),
            // Earnings stub — the payroll feature computes this later.
            // TODO(payroll): replace with the driver's real daily earnings.
            Text('Gains du jour : — (bientôt : paie)',
                style: TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Preuve de livraison', style: TchopTypography.titleLarge),
              const SizedBox(height: 4),
              const Text(
                'Photo du colis remis + signature du client.',
                style: TextStyle(color: TchopColors.textSecondary),
              ),
              const SizedBox(height: 16),
              // Photo step
              Row(
                children: [
                  Expanded(
                    child: _photo == null
                        ? OutlinedButton.icon(
                            onPressed: _takePhoto,
                            icon: const Icon(Icons.photo_camera),
                            label: const Text('Prendre la photo'),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_photo!, height: 140,
                                fit: BoxFit.cover),
                          ),
                  ),
                  if (_photo != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Reprendre',
                      onPressed: _takePhoto,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Signature du client'),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(_sigController.clear),
                    child: const Text('Effacer'),
                  ),
                ],
              ),
              SignaturePad(controller: _sigController),
              const SizedBox(height: 8),
              const Text(
                'La position GPS est capturée automatiquement à l’envoi.',
                style: TextStyle(color: TchopColors.textSecondary, fontSize: 12),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: TchopColors.error)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Valider la livraison'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
