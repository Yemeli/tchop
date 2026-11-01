import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/tchop_colors.dart';
import '../../core/responsive.dart';
import '../../core/services_scope.dart';
import '../../design_system/tchop_typography.dart';
import '../menu/daypart.dart';
import 'cart.dart';
import 'order_detail_screen.dart';
import 'order_models.dart';
import 'order_repository.dart';
import 'order_widgets.dart';

OrderRepository _ordersOf(BuildContext context) {
  final scope = ServicesScope.of(context);
  return scope.orderRepository ??
      OrderRepository(db: scope.db, syncEngine: scope.syncEngine);
}

/// Customer storefront: menu browser → cart → checkout.
///
/// - Renders the latest **published** snapshot ([PublishedMenu.version]) and
///   stamps that version on the cart — the server rejects the order when the
///   menu was republished in between (stale_menu 409).
/// - The cart subscribes to the 86 Realtime channel while open: an item that
///   goes 86 is removed with "Épuisé — retiré du panier".
/// - Checkout goes through the outbox (`order/create`): the order appears
///   instantly, marked "En attente de synchro" when offline.
class CustomerMenuScreen extends StatefulWidget {
  const CustomerMenuScreen({
    super.key,
    required this.tenantId,
    this.channel = OrderChannel.app,
    this.tableNumber,
    this.restaurantName,
  });

  final String tenantId;

  /// [OrderChannel.app] normally, [OrderChannel.qrTable] from a table link.
  final String channel;
  final int? tableNumber;
  final String? restaurantName;

  @override
  State<CustomerMenuScreen> createState() => _CustomerMenuScreenState();
}

class _CustomerMenuScreenState extends State<CustomerMenuScreen> {
  late final OrderCart _cart;
  late final AvailabilityCartBinder _binder;
  PublishedMenu? _menu;
  bool _loading = true;
  String? _error;
  StreamSubscription<OrderCreateConflict>? _conflictSub;
  final Set<String> _pendingKeys = {};

  OrderRepository get _orders => _ordersOf(context);
  bool _depsReady = false;

  @override
  void initState() {
    super.initState();
    _cart = OrderCart(tenantId: widget.tenantId);
    _binder = AvailabilityCartBinder(
      cart: _cart,
      onNotice: (notice) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(notice)));
        }
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ServicesScope.of() subscribes to the inherited widget — not allowed
    // in initState.
    if (_depsReady) return;
    _depsReady = true;
    _conflictSub = _orders.createConflicts.listen(_onCreateConflict);
    _load();
  }

  Future<void> _load() async {
    try {
      final menu = await _orders.loadPublishedMenu(widget.tenantId);
      final fee = await _orders.deliveryFeeFor(widget.tenantId);
      if (!mounted) return;
      setState(() {
        _menu = menu;
        _loading = false;
        _error = menu == null ? 'Menu indisponible pour le moment.' : null;
      });
      _cart.setDeliveryFee(fee);
      if (menu != null) _binder.attach(widget.tenantId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger le menu : $e';
      });
    }
  }

  @override
  void dispose() {
    _conflictSub?.cancel();
    _binder.detach();
    _cart.dispose();
    super.dispose();
  }

  /// The server rejected our optimistic order (stale menu / price / 86):
  /// restore the cart lines and explain in French.
  void _onCreateConflict(OrderCreateConflict conflict) {
    if (!_pendingKeys.remove(conflict.clientMutationId)) return;
    if (!mounted || _menu == null) return;
    final menu = _menu!;
    final byId = {for (final i in menu.items) i.id: i};
    _cart.clear();
    for (final line in conflict.lines) {
      final item = byId[line.itemId];
      if (item == null || !item.available) continue;
      for (var n = 0; n < line.qty; n++) {
        _cart.addItem(
          itemId: item.id,
          name: item.name,
          unitPriceFcfa: item.priceFcfa, // refreshed snapshot price
          menuVersion: menu.version,
        );
      }
    }
    final messages = conflict.conflicts
        .map((c) => c.messageFr((id) => byId[id]?.name ?? id))
        .join('\n');
    showDialog<void>(
      context: context,
      builder: (context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AlertDialog(
          title: const Text('Le menu a changé'),
          content: Text(
            '$messages\n\nVotre panier a été mis à jour avec les prix et '
            'disponibilités actuels.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Revoir mon panier'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.restaurantName ?? 'Menu'),
        actions: [
          ListenableBuilder(
            listenable: _cart,
            builder: (context, _) => Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  tooltip: 'Panier',
                  icon: const Icon(Icons.shopping_bag_outlined),
                  onPressed: _cart.isEmpty ? null : _openCart,
                ),
                if (_cart.itemCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: TchopColors.error,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${_cart.itemCount}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _buildMenu(),
      bottomNavigationBar: ListenableBuilder(
        listenable: _cart,
        builder: (context, _) {
          if (_cart.isEmpty) return const SizedBox.shrink();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                icon: const Icon(Icons.shopping_bag_outlined),
                label: Text(
                  'Voir le panier · ${formatFcfa(_cart.total)}',
                ),
                onPressed: _openCart,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMenu() {
    final menu = _menu!;
    final now = DateTime.now();
    final daypart = activeDaypart(menu.dayparts, now);
    return CenteredContent(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DaypartBanner(daypart: daypart, dayparts: menu.dayparts, now: now),
          if (widget.channel == OrderChannel.qrTable &&
              widget.tableNumber != null) ...[
            const SizedBox(height: 8),
            Chip(
              avatar: const Icon(Icons.qr_code_2, size: 18),
              label: Text('Table ${widget.tableNumber}'),
            ),
          ],
          const SizedBox(height: 8),
          for (final category in menu.categories) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(category.name, style: TchopTypography.displayMedium),
            ),
            _MenuItemGrid(
              items: menu.itemsIn(category.id),
              menuVersion: menu.version,
              cart: _cart,
            ),
          ],
          if (menu.categories.isEmpty)
            _MenuItemGrid(
              items: menu.items,
              menuVersion: menu.version,
              cart: _cart,
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _openCart() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => CenteredContent(
        maxWidth: 560,
        child: _CartSheet(
          cart: _cart,
          channel: widget.channel,
          tableNumber: widget.tableNumber,
          orders: _orders,
          onOrdered: _onOrdered,
        ),
      ),
    );
  }

  void _onOrdered(String orderId, String clientMutationId) {
    _pendingKeys.add(clientMutationId);
    _cart.clear();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailScreen(
          tenantId: widget.tenantId,
          orderId: orderId,
        ),
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Commande envoyée ! Suivez sa préparation en direct.',
        ),
      ),
    );
  }
}

class _DaypartBanner extends StatelessWidget {
  const _DaypartBanner({
    required this.daypart,
    required this.dayparts,
    required this.now,
  });

  final Daypart? daypart;
  final List<Daypart> dayparts;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final d = daypart;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: d == null ? TchopColors.surfaceMuted : TchopColors.success.withValues(alpha: 31),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            d == null ? Icons.nightlight_outlined : Icons.schedule,
            color: d == null ? TchopColors.textSecondary : TchopColors.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              d == null
                  ? 'Fermé actuellement — revenez pendant le service.'
                  : 'Service en cours : ${d.name} · ${d.startLabel}–${d.endLabel}',
              style: TchopTypography.bodyMedium.copyWith(
                color: d == null
                    ? TchopColors.textSecondary
                    : TchopColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Menu items as a responsive grid: 2 columns on phones, 3 on tablets,
/// 5 on desktop (mirrors the home screen's dish grid).
class _MenuItemGrid extends StatelessWidget {
  const _MenuItemGrid({
    required this.items,
    required this.menuVersion,
    required this.cart,
  });

  final List<OrderMenuItem> items;
  final int menuVersion;
  final OrderCart cart;

  @override
  Widget build(BuildContext context) {
    final columns = context.responsiveValue(mobile: 2, tablet: 3, desktop: 5);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _MenuGridCard(
        item: items[i],
        menuVersion: menuVersion,
        cart: cart,
      ),
    );
  }
}

class _MenuGridCard extends StatelessWidget {
  const _MenuGridCard({
    required this.item,
    required this.menuVersion,
    required this.cart,
  });

  final OrderMenuItem item;
  final int menuVersion;
  final OrderCart cart;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TODO(3d-viewer): lazy 3D dish viewer as the signature visual.
            Expanded(
              child: Center(
                child: _ItemPhoto(item: item, size: 88),
              ),
            ),
            Text(
              item.name,
              style: TchopTypography.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.description.isNotEmpty)
              Text(
                item.description,
                style: TchopTypography.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 2),
            item.available
                ? Text(
                    formatFcfa(item.priceFcfa),
                    style: TchopTypography.price,
                  )
                : const Text(
                    'Épuisé',
                    style: TextStyle(
                      color: TchopColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
            if (item.available) ...[
              const SizedBox(height: 2),
              _QtyStepper(
                item: item,
                menuVersion: menuVersion,
                cart: cart,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Add-to-cart button that turns into a − qty + stepper.
/// Shared by the grid card (extracted from the old menu row, logic
/// unchanged).
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
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
        if (qty == 0) {
          return IconButton.filled(
            tooltip: 'Ajouter',
            onPressed: () => cart.addItem(
              itemId: item.id,
              name: item.name,
              unitPriceFcfa: item.priceFcfa,
              menuVersion: menuVersion,
            ),
            icon: const Icon(Icons.add),
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Retirer',
              onPressed: () => cart.setQty(item.id, qty - 1),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$qty', style: TchopTypography.titleMedium),
            IconButton(
              tooltip: 'Ajouter',
              onPressed: () => cart.addItem(
                itemId: item.id,
                name: item.name,
                unitPriceFcfa: item.priceFcfa,
                menuVersion: menuVersion,
              ),
              icon: const Icon(Icons.add_circle),
            ),
          ],
        );
      },
    );
  }
}

class _ItemPhoto extends StatelessWidget {
  const _ItemPhoto({required this.item, this.size = 64});

  final OrderMenuItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    // TODO(3d-viewer): lazy 3D dish viewer as the signature visual.
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: item.photoUrl == null
            ? Container(
                color: TchopColors.surfaceMuted,
                child: const Icon(Icons.restaurant,
                    size: 28, color: TchopColors.textSecondary),
              )
            : Image.network(
                item.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: TchopColors.surfaceMuted,
                  child: const Icon(Icons.restaurant,
                      size: 28, color: TchopColors.textSecondary),
                ),
              ),
      ),
    );
  }
}

/// Bottom sheet: cart lines → totals → checkout form → `order/create`.
class _CartSheet extends StatefulWidget {
  const _CartSheet({
    required this.cart,
    required this.channel,
    required this.orders,
    required this.onOrdered,
    this.tableNumber,
  });

  final OrderCart cart;
  final String channel;
  final OrderRepository orders;
  final void Function(String orderId, String clientMutationId) onOrdered;
  final int? tableNumber;

  @override
  State<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<_CartSheet> {
  bool _checkout = false;
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: widget.cart,
            builder: (context, _) {
              final cart = widget.cart;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        _checkout ? 'Finaliser la commande' : 'Panier',
                        style: TchopTypography.displayMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Fermer',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (!_checkout) ...[
                    for (final line in cart.lines)
                      _CartLineRow(
                        line: line,
                        onChanged: (qty) =>
                            cart.setQty(line.itemId, qty),
                      ),
                    const Divider(),
                    _TotalRow(
                        label: 'Sous-total',
                        value: formatFcfa(cart.subtotal)),
                    _TotalRow(
                      label: widget.channel == OrderChannel.qrTable
                          ? 'Service à table'
                          : 'Livraison',
                      value: cart.deliveryFeeFcfa == 0
                          ? 'Gratuite'
                          : formatFcfa(cart.deliveryFeeFcfa),
                    ),
                    _TotalRow(
                      label: 'Total',
                      value: formatFcfa(cart.total),
                      bold: true,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: cart.isEmpty
                          ? null
                          : () => setState(() => _checkout = true),
                      child: const Text('Commander'),
                    ),
                  ] else ...[
                    CheckoutForm(
                      showAddress:
                          widget.channel != OrderChannel.qrTable,
                      submitLabel: _sending
                          ? 'Envoi…'
                          : 'Confirmer · ${formatFcfa(cart.total)}',
                      onSubmit: ({
                        required String name,
                        required String phone,
                        required String address,
                        required String paymentMethod,
                      }) =>
                          _submitOrder(
                        name: name,
                        phone: phone,
                        address: address,
                        paymentMethod: paymentMethod,
                      ),
                    ),
                    TextButton(
                      onPressed: _sending
                          ? null
                          : () => setState(() => _checkout = false),
                      child: const Text('Retour au panier'),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _submitOrder({
    required String name,
    required String phone,
    required String address,
    required String paymentMethod,
  }) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final cart = widget.cart;
      final result = await widget.orders.createOrder(
        tenantId: cart.tenantId,
        channel: widget.channel,
        lines: cart.toOrderLines(),
        menuVersion: cart.menuVersion ?? 0,
        deliveryFee: cart.deliveryFeeFcfa,
        customerName: name,
        customerPhone: phone,
        address: widget.channel == OrderChannel.qrTable ? null : address,
        tableNumber: widget.tableNumber,
        paymentMethod: paymentMethod,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // close the sheet
      widget.onOrdered(result.orderId, result.clientMutationId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec de la commande : $e')),
      );
    }
  }
}

class _CartLineRow extends StatelessWidget {
  const _CartLineRow({required this.line, required this.onChanged});

  final CartLine line;
  final void Function(int qty) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name, style: TchopTypography.titleMedium),
                Text(
                  '${formatFcfa(line.unitPriceFcfa)} × ${line.qty}',
                  style: TchopTypography.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => onChanged(line.qty - 1),
          ),
          Text('${line.qty}'),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => onChanged(line.qty + 1),
          ),
          SizedBox(
            width: 80,
            child: Text(
              formatFcfa(line.lineTotal),
              textAlign: TextAlign.right,
              style: TchopTypography.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? TchopTypography.titleMedium.copyWith(fontWeight: FontWeight.w800)
        : TchopTypography.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
