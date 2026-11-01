import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/responsive.dart';
import '../../core/services_scope.dart';
import '../../core/session/session_context.dart';
import '../../data/database/tchop_database.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import 'menu_models.dart';
import 'menu_permissions.dart';

/// 86 (sold-out) board, behavior depends on the role:
/// - owner / manager / head chef: direct toggle switches
///   ([MenuPermissions.canToggle86]);
/// - kitchen staff: a "Demander épuisement" button per available item →
///   `menu/request_86` outbox op → lands in the manager's approvals inbox
///   ([MenuPermissions.canRequest86]);
/// - everyone else: read-only availability list.
///
/// Reached from the kitchen ticket board ("86" button) and from the menu
/// studio. The head chef gets the direct toggle here as well.
class EightySixScreen extends StatefulWidget {
  const EightySixScreen({super.key});

  @override
  State<EightySixScreen> createState() => _EightySixScreenState();
}

class _EightySixScreenState extends State<EightySixScreen> {
  MenuDraftDoc? _doc;
  Map<String, bool> _availability = {};
  StreamSubscription<List<ItemAvailability>>? _availabilitySub;
  StreamSubscription<MenuDraftDoc>? _draftSub;
  String? _tenantId;
  String? _role;
  String? _userId;
  final Set<String> _requesting = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tenantId != null) return;
    final services = ServicesScope.of(context);
    final session = SessionScope.maybeOf(context);
    _tenantId = session?.tenantId ?? 'demo-tenant';
    _role = session?.role ?? MenuRoles.kitchen;
    _userId = session?.userId;
    final tenantId = _tenantId!;
    services.menuRepository.loadDraft(tenantId).then((doc) {
      if (mounted) setState(() => _doc = doc);
    });
    _draftSub = services.menuRepository.watchDraft(tenantId).listen((doc) {
      if (mounted) setState(() => _doc = doc);
    });
    _availabilitySub =
        services.db.watchAvailabilityForTenant(tenantId).listen((rows) {
      if (mounted) {
        setState(
            () => _availability = {for (final r in rows) r.itemId: r.available});
      }
    });
  }

  @override
  void dispose() {
    _availabilitySub?.cancel();
    _draftSub?.cancel();
    super.dispose();
  }

  bool _isAvailable(String itemId) => _availability[itemId] ?? true;

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final canToggle = MenuPermissions.canToggle86(_role);
    final canRequest = MenuPermissions.canRequest86(_role);
    return Scaffold(
      appBar: AppBar(title: const Text('Disponibilités · 86')),
      body: doc == null
          ? const Center(child: CircularProgressIndicator())
          : CenteredContent(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (canRequest)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Un plat est épuisé ? Demandez son retrait — le manager valide.',
                        style: TchopTypography.bodySmall,
                      ),
                    ),
                  for (final category in doc.sortedCategories)
                    _CategorySection(
                      title: category.name,
                      items: doc.itemsInCategory(category.id),
                      itemCard: (item) =>
                          _row(context, item, canToggle, canRequest),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _row(
      BuildContext context, MenuItem item, bool canToggle, bool canRequest) {
    final available = _isAvailable(item.id);
    Widget trailing;
    if (canToggle) {
      trailing = Switch(
        value: available,
        activeThumbColor: TchopColors.success,
        onChanged: (value) =>
            ServicesScope.of(context).availabilityBroadcaster.setAvailability(
                  tenantId: _tenantId!,
                  itemId: item.id,
                  available: value,
                  requestedBy: _userId,
                ),
      );
    } else if (canRequest && available) {
      trailing = _requesting.contains(item.id)
          ? const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : OutlinedButton(
              onPressed: () => _request86(context, item),
              child: const Text('Demander épuisement'),
            );
    } else {
      trailing = Icon(
        available ? Icons.check_circle_outline : Icons.block,
        color: available ? TchopColors.success : TchopColors.error,
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        title: Text(item.name,
            style: TchopTypography.bodyMedium
                .copyWith(fontWeight: FontWeight.w600)),
        subtitle: available
            ? null
            : const Text('Épuisé',
                style: TextStyle(
                    color: TchopColors.error, fontWeight: FontWeight.w600)),
        trailing: trailing,
      ),
    );
  }

  Future<void> _request86(BuildContext context, MenuItem item) async {
    setState(() => _requesting.add(item.id));
    try {
      await ServicesScope.of(context).menuRepository.request86(
            tenantId: _tenantId!,
            itemId: item.id,
            itemName: item.name,
            requestedBy: _userId,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Demande envoyée pour « ${item.name} » — en attente du manager.')));
      }
    } finally {
      if (mounted) setState(() => _requesting.remove(item.id));
    }
  }
}

/// One category of the 86 board: item cards in a responsive grid —
/// single column on phones, 2 on tablets, 3 on desktops.
class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.title,
    required this.items,
    required this.itemCard,
  });

  final String title;
  final List<MenuItem> items;
  final Widget Function(MenuItem item) itemCard;

  @override
  Widget build(BuildContext context) {
    final columns =
        context.responsiveValue(mobile: 1, tablet: 2, desktop: 3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(title, style: TchopTypography.titleMedium),
        ),
        if (columns == 1)
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: itemCard(item),
            )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 88,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => itemCard(items[index]),
          ),
      ],
    );
  }
}
