import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/responsive.dart';
import '../../core/services_scope.dart';
import '../../core/session/session_context.dart';
import '../../data/database/tchop_database.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import 'daypart.dart';
import 'menu_models.dart';
import 'menu_permissions.dart';
import 'menu_studio_controller.dart';

/// Menu studio (manager flavor): draft editor → publish.
///
/// - **Brouillon**: categories (add/rename/reorder) + items per category.
/// - **Horaires**: daypart windows (Petit-déjeuner / Déjeuner / Dîner).
/// - **Approbations**: owner/manager inbox (price changes >10%, 86 requests).
/// - **Historique**: published version list.
///
/// RBAC is enforced in the UI via [MenuPermissions] (mirroring the
/// controller): the head chef sees item names with the 86 toggle only — no
/// price fields, no publish button.
class MenuStudioScreen extends StatefulWidget {
  const MenuStudioScreen({super.key});

  @override
  State<MenuStudioScreen> createState() => _MenuStudioScreenState();
}

class _MenuStudioScreenState extends State<MenuStudioScreen> {
  MenuStudioController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      final services = ServicesScope.of(context);
      final session = SessionScope.maybeOf(context);
      _controller = MenuStudioController(
        repository: services.menuRepository,
        availabilityBroadcaster: services.availabilityBroadcaster,
        db: services.db,
        syncEngine: services.syncEngine,
        tenantId: session?.tenantId ?? 'demo-tenant',
        role: session?.role ?? MenuRoles.manager,
        userId: session?.userId,
      )..load();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tabs = <Tab>[
          const Tab(text: 'Brouillon'),
          const Tab(text: 'Horaires'),
          if (controller.canReviewApprovals)
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Approbations'),
                  const SizedBox(width: 6),
                  _CountBadge(
                      count: controller.doc?.pendingApprovals.length ?? 0),
                ],
              ),
            ),
          const Tab(text: 'Historique'),
        ];
        return DefaultTabController(
          length: tabs.length,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Studio menu'),
              actions: [
                _SaveIndicator(controller: controller),
                if (controller.canPublish)
                  TextButton.icon(
                    onPressed: controller.publishing
                        ? null
                        : () => _confirmPublish(context, controller),
                    icon: controller.publishing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.publish_outlined),
                    label: const Text('Publier'),
                  ),
              ],
              bottom: TabBar(tabs: tabs, isScrollable: true),
            ),
            body: controller.loading
                ? const Center(child: CircularProgressIndicator())
                : controller.error != null && controller.doc == null
                    ? Center(child: Text('Erreur : ${controller.error}'))
                    : CenteredContent(
                        child: TabBarView(
                          children: [
                            _DraftTab(controller: controller),
                            _DaypartsTab(controller: controller),
                            if (controller.canReviewApprovals)
                              _ApprovalsTab(controller: controller),
                            _HistoryTab(controller: controller),
                          ],
                        ),
                      ),
          ),
        );
      },
    );
  }

  Future<void> _confirmPublish(
      BuildContext context, MenuStudioController controller) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _dialogShell(
        AlertDialog(
          title: const Text('Publier le menu ?'),
          content: const Text(
              'Le brouillon devient une version immuable, visible par les clients.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Publier')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      final published = await controller.publish();
      if (context.mounted && !published) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Échec de la publication : ${controller.error}')),
        );
      }
    }
  }
}

/// "Enregistré" / "En attente de synchro" badge.
class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.controller});
  final MenuStudioController controller;

  @override
  Widget build(BuildContext context) {
    final pending = controller.syncPending;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        avatar: Icon(
          pending ? Icons.cloud_off_outlined : Icons.check,
          size: 16,
          color: pending ? TchopColors.warning : TchopColors.success,
        ),
        label: Text(
          pending ? 'En attente de synchro' : 'Enregistré',
          style: TchopTypography.bodySmall,
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: TchopColors.error,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$count',
          style: TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

// ------------------------------------------------------------------
// Brouillon tab
// ------------------------------------------------------------------

class _DraftTab extends StatelessWidget {
  const _DraftTab({required this.controller});
  final MenuStudioController controller;

  @override
  Widget build(BuildContext context) {
    final doc = controller.doc;
    if (doc == null) return const SizedBox.shrink();
    final categories = doc.sortedCategories;
    return Column(
      children: [
        if (controller.notice != null)
          _NoticeBanner(
              message: controller.notice!,
              onClose: controller.clearNotice),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: categories.length + 1,
            onReorder: (oldIndex, newIndex) {
              if (oldIndex < categories.length &&
                  newIndex <= categories.length) {
                controller.reorderCategories(oldIndex, newIndex);
              }
            },
            itemBuilder: (context, index) {
              if (index == categories.length) {
                // Footer: add-category (not reorderable).
                return Container(
                  key: const ValueKey('__add_category__'),
                  margin: const EdgeInsets.only(top: 8),
                  child: controller.canEditItems
                      ? OutlinedButton.icon(
                          onPressed: () =>
                              _promptText(context, 'Nouvelle catégorie',
                                  (name) => controller.addCategory(name)),
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter une catégorie'),
                        )
                      : const SizedBox.shrink(),
                );
              }
              final category = categories[index];
              return _CategoryCard(
                key: ValueKey(category.id),
                controller: controller,
                category: category,
                items: doc.itemsInCategory(category.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    super.key,
    required this.controller,
    required this.category,
    required this.items,
  });

  final MenuStudioController controller;
  final MenuCategory category;
  final List<MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (controller.canEditItems)
                  const Icon(Icons.drag_handle, color: TchopColors.textSecondary, size: 20),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(category.name,
                      style: TchopTypography.titleMedium),
                ),
                Text('${items.length} plat${items.length > 1 ? 's' : ''}',
                    style: TchopTypography.bodySmall),
                if (controller.canEditItems)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'rename') {
                        _promptText(context, 'Renommer la catégorie',
                            (name) => controller.renameCategory(category.id, name),
                            initial: category.name);
                      } else if (value == 'delete') {
                        _confirmDeleteCategory(context);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                          value: 'rename', child: Text('Renommer')),
                      PopupMenuItem(
                          value: 'delete', child: Text('Supprimer')),
                    ],
                  ),
              ],
            ),
            const Divider(),
            for (final item in items)
              _ItemTile(controller: controller, item: item),
            if (controller.canEditItems)
              TextButton.icon(
                onPressed: () => _promptText(context, 'Nouveau plat',
                    (name) => controller.addItem(category.id, name)),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter un plat'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteCategory(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _dialogShell(
        AlertDialog(
          title: const Text('Supprimer la catégorie ?'),
          content: const Text(
              'Supprimez d’abord ses plats, ou déplacez-les.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Supprimer')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      final deleted = await controller.deleteCategory(category.id);
      if (!deleted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Catégorie non vide : supprimez ses plats d’abord.')));
      }
    }
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.controller, required this.item});
  final MenuStudioController controller;
  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final available = controller.isAvailable(item.id);
    // Head chef: 86 toggle only — no price fields, no edit dialog.
    final chefOnly = !controller.canEditPrices && controller.canToggle86;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _ItemPhoto(photoUrl: item.photoUrl, name: item.name),
      title: Text(item.name,
          style: TchopTypography.bodyMedium
              .copyWith(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!chefOnly) ...[
            Text(_fcfa(item.priceFcfa), style: TchopTypography.price),
            if (item.description.isNotEmpty)
              Text(item.description,
                  style: TchopTypography.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
          ],
          if (item.pendingApproval)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Chip(
                label: Text('En approbation',
                    style: TextStyle(fontSize: 11)),
                avatar: Icon(Icons.hourglass_empty,
                    size: 14, color: TchopColors.warning),
                visualDensity: VisualDensity.compact,
              ),
            ),
          if (!available)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Chip(
                label: Text('Épuisé',
                    style: TextStyle(fontSize: 11)),
                avatar: Icon(Icons.block,
                    size: 14, color: TchopColors.error),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
      trailing: controller.canToggle86
          ? Switch(
              value: available,
              activeThumbColor: TchopColors.success,
              onChanged: (value) =>
                  controller.toggle86(item.id, value),
            )
          : null,
      onTap: controller.canEditItems && !chefOnly
          ? () => showDialog(
                context: context,
                builder: (_) => _dialogShell(_ItemEditorDialog(
                    controller: controller, item: item)),
              )
          : null,
    );
  }
}

class _ItemPhoto extends StatelessWidget {
  const _ItemPhoto({this.photoUrl, required this.name});
  final String? photoUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    const size = 48.0;
    if (photoUrl == null || photoUrl!.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: TchopColors.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.fastfood_outlined,
            color: TchopColors.textSecondary),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        photoUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: TchopColors.surfaceMuted,
          child: const Icon(Icons.broken_image_outlined, color: TchopColors.textSecondary),
        ),
      ),
    );
  }
}

/// Item editor dialog: name, description, price (FCFA), photo, tags.
/// The price field is only rendered when the role may edit prices.
class _ItemEditorDialog extends StatefulWidget {
  const _ItemEditorDialog({required this.controller, required this.item});
  final MenuStudioController controller;
  final MenuItem item;

  @override
  State<_ItemEditorDialog> createState() => _ItemEditorDialogState();
}

class _ItemEditorDialogState extends State<_ItemEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _tags;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item.name);
    _description = TextEditingController(text: widget.item.description);
    _price = TextEditingController(text: '${widget.item.priceFcfa}');
    _tags = TextEditingController(text: widget.item.tags.join(', '));
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AlertDialog(
      title: const Text('Modifier le plat'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 2,
            ),
            if (controller.canEditPrices)
              TextField(
                controller: _price,
                decoration: const InputDecoration(
                    labelText: 'Prix (FCFA)',
                    helperText:
                        '>10 % vs prix publié → approbation requise'),
                keyboardType: TextInputType.number,
              ),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(
                  labelText: 'Tags (séparés par des virgules)'),
            ),
            const SizedBox(height: 12),
            _uploading
                ? const LinearProgressIndicator()
                : OutlinedButton.icon(
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Changer la photo'),
                  ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _deleteWithConfirm(context),
          child:
              const Text('Supprimer', style: TextStyle(color: TchopColors.error)),
        ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }

  Future<void> _pickPhoto() async {
    setState(() => _uploading = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 80,
      );
      if (picked == null) return;
      final url = await ServicesScope.of(context)
          .menuRepository
          .uploadItemPhoto(
            tenantId: widget.controller.tenantId,
            itemId: widget.item.id,
            file: picked,
          );
      if (!mounted) return;
      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Photo non envoyée (hors ligne ou échec) — réessayez connecté.')));
      } else {
        await widget.controller.setItemPhoto(widget.item, url);
        if (mounted) Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteWithConfirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _dialogShell(
        AlertDialog(
          title: const Text('Supprimer ce plat ?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Supprimer')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await widget.controller.deleteItem(widget.item.id);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _save() async {
    final controller = widget.controller;
    final updated = widget.item.copyWith(
      name: _name.text.trim().isEmpty ? widget.item.name : _name.text.trim(),
      description: _description.text.trim(),
      tags: _tags.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
    );
    await controller.updateItem(updated);
    if (controller.canEditPrices) {
      final price = int.tryParse(_price.text.trim());
      if (price != null) {
        await controller.setItemPrice(updated, price);
      }
    }
    if (mounted) Navigator.pop(context);
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text(message),
      leading: const Icon(Icons.info_outline, color: TchopColors.info),
      actions: [
        TextButton(onPressed: onClose, child: const Text('OK')),
      ],
    );
  }
}

// ------------------------------------------------------------------
// Horaires tab
// ------------------------------------------------------------------

class _DaypartsTab extends StatelessWidget {
  const _DaypartsTab({required this.controller});
  final MenuStudioController controller;

  @override
  Widget build(BuildContext context) {
    final dayparts = controller.doc?.dayparts ?? const <Daypart>[];
    final columns =
        context.responsiveValue(mobile: 1, tablet: 2, desktop: 3);
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 84,
      ),
      itemCount: dayparts.length,
      itemBuilder: (context, index) {
        final daypart = dayparts[index];
        final live = daypart.contains(DateTime.now());
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(daypart.name, style: TchopTypography.titleMedium),
            subtitle: Text(
                '${daypart.startLabel} – ${daypart.endLabel}${live ? ' · en ce moment' : ''}'),
            trailing: live
                ? const Icon(Icons.schedule, color: TchopColors.success)
                : null,
            enabled: controller.canEditItems,
            onTap: controller.canEditItems
                ? () => _editDaypart(context, daypart)
                : null,
          ),
        );
      },
    );
  }

  Future<void> _editDaypart(BuildContext context, Daypart daypart) async {
    Future<TimeOfDay?> pick(TimeOfDay initial) => showTimePicker(
          context: context,
          initialTime: initial,
          helpText: 'Choisir l’heure',
        );
    final start = await pick(
        TimeOfDay(hour: daypart.startMinutes ~/ 60, minute: daypart.startMinutes % 60));
    if (start == null || !context.mounted) return;
    final end = await pick(
        TimeOfDay(hour: daypart.endMinutes ~/ 60, minute: daypart.endMinutes % 60));
    if (end == null || !context.mounted) return;
    await controller.updateDaypart(daypart.copyWith(
      startMinutes: start.hour * 60 + start.minute,
      endMinutes: end.hour * 60 + end.minute,
    ));
  }
}

// ------------------------------------------------------------------
// Approbations tab
// ------------------------------------------------------------------

class _ApprovalsTab extends StatelessWidget {
  const _ApprovalsTab({required this.controller});
  final MenuStudioController controller;

  @override
  Widget build(BuildContext context) {
    final pending = controller.doc?.pendingApprovals ?? const <MenuApproval>[];
    if (pending.isEmpty) {
      return const Center(
          child: Text('Aucune demande en attente.',
              style: TchopTypography.bodyMedium));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: pending.length,
      itemBuilder: (context, index) {
        final approval = pending[index];
        final isPrice = approval.kind == MenuApproval.kindPriceChange;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isPrice
                          ? Icons.price_change_outlined
                          : Icons.block_outlined,
                      color: isPrice
                          ? TchopColors.warning
                          : TchopColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isPrice
                            ? 'Changement de prix : ${approval.itemName}'
                            : 'Épuisement demandé : ${approval.itemName}',
                        style: TchopTypography.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (isPrice)
                  Text(
                    '${_fcfa(approval.oldPriceFcfa ?? 0)} → ${_fcfa(approval.newPriceFcfa ?? 0)}',
                    style: TchopTypography.price,
                  )
                else
                  const Text(
                      'La cuisine demande à marquer ce plat comme épuisé.'),
                if (approval.requestedBy != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Demandé par ${approval.requestedBy}',
                        style: TchopTypography.bodySmall),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => isPrice
                          ? controller.rejectPrice(approval.id)
                          : controller.resolve86Request(approval.id, false),
                      child: const Text('Refuser'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => isPrice
                          ? controller.approvePrice(approval.id)
                          : controller.resolve86Request(approval.id, true),
                      child: const Text('Approuver'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------
// Historique tab
// ------------------------------------------------------------------

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.controller});
  final MenuStudioController controller;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MenuSnapshot>>(
      future: controller.versionHistory(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final versions = snapshot.data!;
        if (versions.isEmpty) {
          return const Center(
              child: Text('Aucune version publiée pour l’instant.',
                  style: TchopTypography.bodyMedium));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: versions.length,
          itemBuilder: (context, index) {
            final version = versions[index];
            final when = version.publishedAt;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text('${version.version}',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                title: Text('Version ${version.version}',
                    style: TchopTypography.titleMedium),
                subtitle: Text(
                  when == null
                      ? 'date inconnue'
                      : 'publiée le ${_formatDateTime(when.toLocal())}',
                  style: TchopTypography.bodySmall,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ------------------------------------------------------------------
// Helpers
// ------------------------------------------------------------------

/// Caps dialog width on wide screens (phones are unaffected — they are
/// already narrower than the cap).
Widget _dialogShell(Widget dialog) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: dialog,
      ),
    );

/// "2500" → "2 500 FCFA".
String _fcfa(int amount) {
  final digits = amount.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    buffer.write(digits[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buffer.write(' ');
  }
  return '${buffer.toString()} FCFA';
}

/// "27/09 à 14:02".
String _formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)} à ${two(dt.hour)}:${two(dt.minute)}';
}

Future<void> _promptText(
  BuildContext context,
  String title,
  Future<void> Function(String) onSubmit, {
  String? initial,
}) async {
  final textController = TextEditingController(text: initial ?? '');
  final value = await showDialog<String>(
    context: context,
    builder: (context) => _dialogShell(
      AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nom'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, textController.text),
              child: const Text('OK')),
        ],
      ),
    ),
  );
  textController.dispose();
  if (value != null && value.trim().isNotEmpty) {
    await onSubmit(value);
  }
}
