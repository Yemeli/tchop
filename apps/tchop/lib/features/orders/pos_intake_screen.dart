import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/responsive.dart';
import '../../design_system/tchop_colors.dart';
import '../../core/services_scope.dart';
import '../../design_system/tchop_typography.dart';
import '../payments/cash_close_screen.dart';
import 'cart.dart';
import 'order_models.dart';
import 'order_repository.dart';
import 'receipt_widget.dart';

/// Secretary / POS flavor: full counter workstation.
///
/// - Channel selector (Téléphone / WhatsApp / Comptoir) → stamped on the
///   canonical `order/create` payload.
/// - Quick item pad (tap = +1) fed by the published snapshot, with
///   category chips for fast filtering.
/// - Running ticket with quantities (+/− steppers).
/// - Discount line: amount + reason, recorded as `discount_fcfa` /
///   `discount_reason` on `order/create` → server-clamped to the subtotal
///   and audit-logged (`order.discount`) for the manager alerts feed.
/// - Payment method selector → "Encaisser" creates the order and opens the
///   instant receipt view (printable-style ticket).
/// - App-bar shortcut to the daily cash-up (`CashCloseScreen`).
class PosIntakeScreen extends StatefulWidget {
  const PosIntakeScreen({super.key, required this.tenantId});

  final String tenantId;

  @override
  State<PosIntakeScreen> createState() => _PosIntakeScreenState();
}

class _PosIntakeScreenState extends State<PosIntakeScreen> {
  late final OrderCart _cart;
  PublishedMenu? _menu;
  bool _loading = true;

  String _channel = OrderChannel.phone;
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _discountController = TextEditingController();
  final _discountReasonController = TextEditingController();
  String? _lookupHint;
  String _paymentMethod = OrderPaymentMethod.cash;
  bool _sending = false;

  OrderRepository _orders(BuildContext context) {
    final scope = ServicesScope.of(context);
    return scope.orderRepository ??
        OrderRepository(db: scope.db, syncEngine: scope.syncEngine);
  }

  @override
  void initState() {
    super.initState();
    _cart = OrderCart(tenantId: widget.tenantId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // _orders(context) subscribes to ServicesScope — not allowed in
    // initState.
    if (_loading) _load();
  }

  Future<void> _load() async {
    try {
      final menu = await _orders(context).loadPublishedMenu(widget.tenantId);
      if (!mounted) return;
      setState(() {
        _menu = menu;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _cart.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    _discountController.dispose();
    _discountReasonController.dispose();
    super.dispose();
  }

  /// Counter discount parsed from the field, clamped to the subtotal —
  /// mirrors the server clamp so the optimistic total never goes negative.
  int get _discountFcfa {
    final raw =
        int.tryParse(_discountController.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
            0;
    return raw.clamp(0, _cart.subtotal);
  }

  Future<void> _lookupPhone() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;
    final hit = await _orders(context)
        .lookupCustomerByPhone(widget.tenantId, phone);
    if (!mounted) return;
    setState(() {
      if (hit != null) {
        _nameController.text = hit.name;
        _lookupHint = 'Client retrouvé : ${hit.name}';
      } else {
        _lookupHint = 'Nouveau client — nom requis ci-dessous.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caisse — nouvelle vente'),
        actions: [
          IconButton(
            tooltip: 'Clôture de caisse du jour',
            icon: const Icon(Icons.calculate_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CashCloseScreen()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _menu == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aucun menu publié. Publiez le menu depuis le studio '
                      'avant de prendre des commandes.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ResponsiveLayout(
                  // Desktop: master-detail — item pad takes the room, the
                  // ticket panel keeps a fixed readable width.
                  desktop: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _itemPad()),
                      SizedBox(width: 380, child: _ticketPanel()),
                    ],
                  ),
                  // Mobile / tablet: the existing side-by-side work area.
                  mobile: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Item pad (left / main).
                      Expanded(
                        flex: 3,
                        child: _itemPad(),
                      ),
                      const VerticalDivider(width: 1),
                      // Ticket (right).
                      Expanded(
                        flex: 2,
                        child: _ticketPanel(),
                      ),
                    ],
                  ),
                ),
    );
  }

  /// Quick item pad for the current layout (desktop or mobile/tablet).
  Widget _itemPad() => _ItemPad(menu: _menu!, cart: _cart);

  /// Running ticket panel for the current layout. Carries the channel,
  /// customer, discount, payment and submit wiring — cart logic untouched.
  Widget _ticketPanel() => _TicketPanel(
        cart: _cart,
        channel: _channel,
        onChannel: (c) => setState(() => _channel = c),
        phoneController: _phoneController,
        nameController: _nameController,
        lookupHint: _lookupHint,
        onLookup: _lookupPhone,
        paymentMethod: _paymentMethod,
        onPaymentMethod: (m) => setState(() => _paymentMethod = m),
        discountController: _discountController,
        discountReasonController: _discountReasonController,
        onDiscountChanged: () => setState(() {}),
        sending: _sending,
        onSubmit: _submit,
      );

  Future<void> _submit() async {
    if (_sending || _cart.isEmpty) return;
    final name = _nameController.text.trim();
    final phone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (name.length < 2 || phone.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nom et téléphone du client requis.'),
        ),
      );
      return;
    }
    final discount = _discountFcfa;
    final discountReason = _discountReasonController.text.trim();
    if (discount > 0 && discountReason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Motif de la remise requis (traçabilité).'),
        ),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final cart = _cart;
      final lines = cart.toOrderLines();
      final itemNames = {
        for (final i in _menu?.items ?? <OrderMenuItem>[]) i.id: i.name,
      };
      final result = await _orders(context).createOrder(
        tenantId: widget.tenantId,
        channel: _channel,
        lines: lines,
        menuVersion: cart.menuVersion ?? _menu?.version ?? 0,
        deliveryFee: 0, // counter/phone orders: no delivery fee by default
        customerName: name,
        customerPhone:
            phone.startsWith('237') ? '+$phone' : '+237$phone',
        paymentMethod: _paymentMethod,
        discountFcfa: discount,
        discountReason: discount > 0 ? discountReason : null,
      );
      if (!mounted) return;
      final receipt = PosReceipt(
        orderId: result.orderId,
        lines: lines,
        itemNames: itemNames,
        subtotalFcfa: cart.subtotal,
        discountFcfa: discount,
        discountReason: discount > 0 ? discountReason : null,
        deliveryFeeFcfa: 0,
        totalFcfa: cart.total - discount,
        paymentMethod: _paymentMethod,
        channel: _channel,
        customerName: name,
        createdAt: DateTime.now(),
      );
      cart.clear();
      _nameController.clear();
      _phoneController.clear();
      _discountController.clear();
      _discountReasonController.clear();
      setState(() {
        _sending = false;
        _lookupHint = null;
      });
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReceiptScreen(
            tenantId: widget.tenantId,
            receipt: receipt,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec : $e')),
      );
    }
  }
}

/// Quick item pad: one tap = +1. Unavailable items are greyed out.
class _ItemPad extends StatelessWidget {
  const _ItemPad({required this.menu, required this.cart});

  final PublishedMenu menu;
  final OrderCart cart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final category in menu.categories) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(category.name,
                style: TchopTypography.titleMedium),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in menu.itemsIn(category.id))
                _PadButton(item: item, menuVersion: menu.version, cart: cart),
            ],
          ),
        ],
        if (menu.categories.isEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in menu.items)
                _PadButton(item: item, menuVersion: menu.version, cart: cart),
            ],
          ),
      ],
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    required this.item,
    required this.menuVersion,
    required this.cart,
  });

  final OrderMenuItem item;
  final int menuVersion;
  final OrderCart cart;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        final qty = cart.qtyOf(item.id);
        return ActionChip(
          avatar: qty > 0
              ? CircleAvatar(
                  radius: 10,
                  child: Text('$qty',
                      style: TextStyle(fontSize: 11)),
                )
              : null,
          label: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                item.available
                    ? formatFcfa(item.priceFcfa)
                    : 'Épuisé',
                style: TextStyle(
                  fontSize: 12,
                  color: item.available ? TchopColors.textSecondary : TchopColors.error,
                ),
              ),
            ],
          ),
          onPressed: item.available
              ? () => cart.addItem(
                    itemId: item.id,
                    name: item.name,
                    unitPriceFcfa: item.priceFcfa,
                    menuVersion: menuVersion,
                  )
              : null,
        );
      },
    );
  }
}

class _TicketPanel extends StatelessWidget {
  const _TicketPanel({
    required this.cart,
    required this.channel,
    required this.onChannel,
    required this.phoneController,
    required this.nameController,
    required this.lookupHint,
    required this.onLookup,
    required this.paymentMethod,
    required this.onPaymentMethod,
    required this.discountController,
    required this.discountReasonController,
    required this.onDiscountChanged,
    required this.sending,
    required this.onSubmit,
  });

  final OrderCart cart;
  final String channel;
  final ValueChanged<String> onChannel;
  final TextEditingController phoneController;
  final TextEditingController nameController;
  final String? lookupHint;
  final VoidCallback onLookup;
  final String paymentMethod;
  final ValueChanged<String> onPaymentMethod;
  final TextEditingController discountController;
  final TextEditingController discountReasonController;
  final VoidCallback onDiscountChanged;
  final bool sending;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        final discountRaw = int.tryParse(discountController.text
                .replaceAll(RegExp(r'[^0-9]'), '')) ??
            0;
        final discount = discountRaw.clamp(0, cart.subtotal);
        final netTotal = cart.total - discount;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text('Canal', style: TchopTypography.titleMedium),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: OrderChannel.phone,
                  label: Text('Tél'),
                  icon: Icon(Icons.phone, size: 16),
                ),
                ButtonSegment(
                  value: OrderChannel.whatsapp,
                  label: Text('WhatsApp'),
                  icon: Icon(Icons.chat, size: 16),
                ),
                ButtonSegment(
                  value: OrderChannel.walkin,
                  label: Text('Comptoir'),
                  icon: Icon(Icons.store, size: 16),
                ),
              ],
              selected: {channel},
              onSelectionChanged: (s) => onChannel(s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Téléphone client',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Rechercher',
                  icon: const Icon(Icons.search),
                  onPressed: onLookup,
                ),
              ),
              onSubmitted: (_) => onLookup(),
            ),
            if (lookupHint != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  lookupHint!,
                  style: TchopTypography.bodySmall
                      .copyWith(color: TchopColors.textSecondary),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom du client',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text('Ticket', style: TchopTypography.titleMedium),
            const SizedBox(height: 4),
            if (cart.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Touchez les articles pour les ajouter.',
                  style: TextStyle(color: TchopColors.textSecondary),
                ),
              ),
            for (final line in cart.lines)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${line.qty} × ${line.name}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      tooltip: '−1',
                      onPressed: () =>
                          cart.setQty(line.itemId, line.qty - 1),
                    ),
                    SizedBox(
                      width: 34,
                      child: Center(
                        child: Text('${line.qty}',
                            style: TchopTypography.price),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      tooltip: '+1',
                      onPressed: () =>
                          cart.setQty(line.itemId, line.qty + 1),
                    ),
                    const SizedBox(width: 4),
                    Text(formatFcfa(line.lineTotal)),
                  ],
                ),
              ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Sous-total', style: TchopTypography.bodyMedium),
                Text(formatFcfa(cart.subtotal)),
              ],
            ),
            const SizedBox(height: 8),
            // --- discount line (audited server-side as order.discount) ---
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Remise',
                  style: TchopTypography.titleMedium.copyWith(fontSize: 14)),
              subtitle: discount > 0
                  ? Text('- ${formatFcfa(discount)}',
                      style: TextStyle(color: TchopColors.success))
                  : const Text('Aucune',
                      style: TextStyle(color: TchopColors.textSecondary)),
              children: [
                TextField(
                  controller: discountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Montant (FCFA)',
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixText: '− ',
                  ),
                  onChanged: (_) => onDiscountChanged(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: discountReasonController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Motif (obligatoire si remise)',
                    hintText: 'Ex : client fidèle, geste commercial',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => onDiscountChanged(),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'La remise est enregistrée avec votre nom — le gérant '
                    'la voit dans les alertes.',
                    style: TextStyle(fontSize: 11, color: TchopColors.textSecondary),
                  ),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total à encaisser',
                    style: TchopTypography.titleMedium),
                Text(
                  formatFcfa(netTotal),
                  style: TchopTypography.price.copyWith(fontSize: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Paiement',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final m in OrderPaymentMethod.all)
                  DropdownMenuItem(
                    value: m,
                    child: Text(OrderPaymentMethod.labelFr(m)),
                  ),
              ],
              onChanged: (v) => onPaymentMethod(v!),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.payments_outlined),
              label: Text(sending ? 'Encaissement…' : 'Encaisser'),
              onPressed: (sending || cart.isEmpty) ? null : onSubmit,
            ),
          ],
        );
      },
    );
  }
}
