import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services_scope.dart';
import '../../core/session/session_context.dart';
import '../../core/ui/state_views.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import '../menu/menu_studio_screen.dart';
import '../orders/order_repository.dart';
import 'inventory_lite.dart';

/// Manual stock counts (Feature 8 — inventory-lite).
///
/// Each published menu item gets a count + an alert threshold. Items at or
/// below threshold surface as "stock bas" warnings on the dashboard and in
/// the alerts center.
///
/// Honest Phase-2 stub: counts are stored on this device only (JSON file);
/// the `inventory/set_count` outbox op is sent so the future server table
/// can replay history. Labeled as such in the UI.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<OrderMenuItem>? _items;
  Map<String, StockCount> _counts = {};
  bool _loading = true;

  InventoryLiteRepository _repo(BuildContext context) =>
      InventoryLiteRepository(
          syncEngine: ServicesScope.of(context).syncEngine);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    final tenantId =
        SessionScope.of(context, listen: false).tenantId ?? '';
    try {
      final orderRepo = ServicesScope.of(context).orderRepository ??
          OrderRepository(
            db: ServicesScope.of(context).db,
            syncEngine: ServicesScope.of(context).syncEngine,
          );
      final menu = await orderRepo.loadPublishedMenu(tenantId);
      final counts = await _repo(context).load(tenantId);
      if (!mounted) return;
      setState(() {
        _items = menu?.items ?? const [];
        _counts = counts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _setCount(OrderMenuItem item, int count) async {
    final tenantId =
        SessionScope.of(context, listen: false).tenantId ?? '';
    final current = _counts[item.id];
    await _repo(context).setCount(
      tenantId: tenantId,
      itemId: item.id,
      itemName: item.name,
      count: count,
      lowThreshold: current?.lowThreshold ?? 5,
    );
    if (!mounted) return;
    setState(() {
      _counts[item.id] = StockCount(
        itemId: item.id,
        itemName: item.name,
        count: count,
        lowThreshold: current?.lowThreshold ?? 5,
        updatedAt: DateTime.now(),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Stock « ${item.name} » : $count')),
    );
  }

  Future<void> _editCount(OrderMenuItem item) async {
    final controller = TextEditingController(
        text: '${_counts[item.id]?.count ?? 0}');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Stock — ${item.name}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Quantité en stock',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
                int.tryParse(controller.text) ?? 0),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (value != null && mounted) await _setCount(item, value);
  }

  @override
  Widget build(BuildContext context) {
    final role = SessionScope.of(context).role ?? '';
    final allowed = role == 'owner' || role == 'manager';
    if (!allowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stock')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'La gestion du stock est réservée au gérant et au propriétaire.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Stock — comptage manuel')),
      body: _loading
          ? const LoadingView(label: 'Chargement du stock…')
          : (_items == null || _items!.isEmpty)
              ? EmptyView(
                  icon: Icons.inventory_2_outlined,
                  title: 'Aucun menu publié',
                  explanation: 'Publiez le menu pour suivre le stock '
                      'de chaque article.',
                  ctaLabel: 'Ouvrir le studio menu',
                  onCta: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const MenuStudioScreen()),
                  ),
                )
              : Column(
                  children: [
                    const OfflineBanner(),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: TchopColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Phase 2 : les comptages sont enregistrés sur cet '
                        'appareil et synchronisés pour un futur stock '
                        'serveur. Les alertes « stock bas » restent locales.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _items!.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final item = _items![i];
                          final count = _counts[item.id];
                          final low = count?.isLow ?? false;
                          return ListTile(
                            leading: low
                                ? const Icon(
                                    Icons.warning_amber_outlined,
                                    color: TchopColors.warning)
                                : const Icon(Icons.inventory_2_outlined),
                            title: Text(item.name,
                                style: TchopTypography.bodyMedium),
                            subtitle: Text(
                              count == null
                                  ? 'Non compté — seuil : 5'
                                  : 'Stock : ${count.count} — seuil : ${count.lowThreshold}',
                              style: TextStyle(
                                  color: low
                                      ? TchopColors.warning
                                      : null),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove),
                                  tooltip: '−1',
                                  onPressed: () => _setCount(item,
                                      (count?.count ?? 1) - 1 < 0 ? 0 : (count?.count ?? 1) - 1),
                                ),
                                SizedBox(
                                  width: 40,
                                  child: Center(
                                    child: Text('${count?.count ?? '—'}',
                                        style: TchopTypography.price),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add),
                                  tooltip: '+1',
                                  onPressed: () => _setCount(
                                      item, (count?.count ?? 0) + 1),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      size: 18),
                                  tooltip: 'Saisir',
                                  onPressed: () => _editCount(item),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
