import 'package:flutter/material.dart';

import '../../design_system/tchop_colors.dart';
import '../../core/branding/tenant_branding_scope.dart';
import '../../design_system/brand_widgets.dart';
import '../payments/cash_close_screen.dart';
import 'order_models.dart';

/// Data for one POS receipt (built at "Encaisser" time — the numbers on the
/// paper match what was charged, even if the sync later adjusts).
class PosReceipt {
  const PosReceipt({
    required this.orderId,
    required this.lines,
    this.itemNames = const {},
    required this.subtotalFcfa,
    required this.discountFcfa,
    this.discountReason,
    required this.deliveryFeeFcfa,
    required this.totalFcfa,
    required this.paymentMethod,
    required this.channel,
    this.customerName,
    required this.createdAt,
  });

  final String orderId;
  final List<OrderLine> lines;

  /// item_id → display name (from the published snapshot at sale time).
  final Map<String, String> itemNames;
  final int subtotalFcfa;
  final int discountFcfa;
  final String? discountReason;
  final int deliveryFeeFcfa;
  final int totalFcfa;
  final String paymentMethod;
  final String channel;
  final String? customerName;
  final DateTime createdAt;

  /// Short human-readable ticket number (last 6 of the UUID, uppercase).
  String get ticketNumber =>
      orderId.replaceAll('-', '').toUpperCase().substring(
          orderId.replaceAll('-', '').length - 6);
}

/// Instant receipt after "Encaisser" — printable-style ticket.
///
/// White "paper" card on the dark app ground: restaurant brand header,
/// lines, totals (with the discount line when one was applied), payment
/// method, ticket number + QR stub, and « Merci de votre visite ! ».
///
/// The QR is a clearly-labeled STUB (deterministic pseudo-pattern from the
/// order id) until a real QR package is wired — it must not be presented as
/// scannable.
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({
    super.key,
    required this.tenantId,
    required this.receipt,
  });

  final String tenantId;
  final PosReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final brand = TenantBrandingScope.of(context);
    final r = receipt;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reçu'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- paper ticket ------------------------------------------------
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 89),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: DefaultTextStyle(
              style: TextStyle(
                color: Colors.black87,
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: BrandLogo(
                      brandName: brand.name,
                      logoUrl: brand.logoUrl,
                      background: brand.primary,
                      radius: 26,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      brand.name.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: 1.2,
                        fontFamily: null,
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      'Ticket N° ${r.ticketNumber}',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Center(
                    child: Text(
                      '${_frDateTime(r.createdAt)} · ${OrderChannel.labelFr(r.channel)}',
                    ),
                  ),
                  if (r.customerName != null && r.customerName!.isNotEmpty)
                    Center(child: Text('Client : ${r.customerName}')),
                  const SizedBox(height: 8),
                  const Text('- - - - - - - - - - - - - - - -'),
                  for (final l in r.lines)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                              '${l.qty} × ${r.itemNames[l.itemId] ?? 'Article'}'),
                        ),
                        Text(formatFcfa(l.qty * l.unitPrice)),
                      ],
                    ),
                  const Text('- - - - - - - - - - - - - - - -'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sous-total'),
                      Text(formatFcfa(r.subtotalFcfa)),
                    ],
                  ),
                  if (r.discountFcfa > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Remise${r.discountReason != null && r.discountReason!.isNotEmpty ? ' (${r.discountReason})' : ''}',
                          style: TextStyle(color: TchopColors.success),
                        ),
                        Text(
                          '- ${formatFcfa(r.discountFcfa)}',
                          style: TextStyle(color: TchopColors.success),
                        ),
                      ],
                    ),
                  if (r.deliveryFeeFcfa > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Livraison'),
                        Text(formatFcfa(r.deliveryFeeFcfa)),
                      ],
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(
                        formatFcfa(r.totalFcfa),
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Paiement'),
                      Text(OrderPaymentMethod.labelFr(r.paymentMethod)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: CustomPaint(
                      size: const Size(96, 96),
                      painter: _QrStubPainter(seed: r.orderId),
                    ),
                  ),
                  const Center(
                    child: Text(
                      '(QR : maquette — non scannable)',
                      style: TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'Merci de votre visite !',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          BrandButton(
            label: 'Nouvelle vente',
            icon: Icons.point_of_sale,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.calculate_outlined, size: 18),
            label: const Text('Clôture de caisse'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CashCloseScreen()),
            ),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Imprimer'),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Impression ticket : bientôt disponible (imprimante Bluetooth).'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _frDateTime(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Deterministic pseudo-QR: a fixed finder-pattern frame + a hashed dot
/// matrix derived from [seed]. Rendered small and always labeled as a
/// stub — never claim it scans.
class _QrStubPainter extends CustomPainter {
  _QrStubPainter({required this.seed});

  final String seed;

  @override
  void paint(Canvas canvas, Size size) {
    final n = 21;
    final cell = size.width / n;
    final fg = Paint()..color = Colors.black87;
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bg);

    var h = 0x811c9dc5;
    for (final c in seed.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    bool bit() {
      h ^= h << 13;
      h &= 0xffffffff;
      h ^= h >> 17;
      h ^= h << 5;
      h &= 0xffffffff;
      return (h & 1) == 1;
    }

    void finder(int ox, int oy) {
      for (var y = 0; y < 7; y++) {
        for (var x = 0; x < 7; x++) {
          final edge = x == 0 || x == 6 || y == 0 || y == 6;
          final core = x >= 2 && x <= 4 && y >= 2 && y <= 4;
          if (edge || core) {
            canvas.drawRect(
              Rect.fromLTWH((ox + x) * cell, (oy + y) * cell, cell, cell),
              fg,
            );
          }
        }
      }
    }

    finder(0, 0);
    finder(n - 7, 0);
    finder(0, n - 7);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final inFinder = (x < 8 && y < 8) ||
            (x >= n - 8 && y < 8) ||
            (x < 8 && y >= n - 8);
        if (!inFinder && bit()) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell, cell),
            fg,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrStubPainter old) => old.seed != seed;
}
