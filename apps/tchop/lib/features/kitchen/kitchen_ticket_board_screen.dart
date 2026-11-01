import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/branding/tenant_branding_scope.dart';
import '../../core/responsive.dart';
import '../../core/services_scope.dart';
import '../../core/session/session_context.dart';
import '../../core/settings/app_settings.dart';
import '../../core/ui/app_settings_scope.dart';
import '../../core/ui/state_views.dart';
import '../../data/supabase_client.dart';
import '../../design_system/brand_widgets.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import '../menu/eighty_six_screen.dart';
import '../menu/menu_models.dart';
import '../orders/order_state_machine.dart';
import 'kds_settings.dart';
import 'kitchen_order_sync.dart';
import 'ticket_alert_beep.dart';
import 'ticket_card.dart';
import 'ticket_detail_sheet.dart';

/// Kitchen Display System: live ticket board for the kitchen staff.
///
/// The board renders ENTIRELY from the local Drift cache — [KitchenOrderSync]
/// fans orders in via Realtime `postgres_changes` + a 60 s PostgREST pull,
/// and every tap goes through [OrderRepository.transitionOrder] (optimistic
/// local flip + `order/transition` outbox op). Offline, the board keeps
/// working: the "Hors ligne" banner shows and mutations queue for later.
class KitchenTicketBoardScreen extends StatefulWidget {
  const KitchenTicketBoardScreen({super.key});

  @override
  State<KitchenTicketBoardScreen> createState() =>
      _KitchenTicketBoardScreenState();
}

class _KitchenTicketBoardScreenState extends State<KitchenTicketBoardScreen>
    with WidgetsBindingObserver {
  static const _columns = [
    (OrderStatus.accepted, 'Nouveau', TchopColors.info),
    (OrderStatus.preparing, 'En préparation', TchopColors.warning),
    (OrderStatus.ready, 'Prêt', TchopColors.success),
  ];

  bool _coreInitialized = false;
  String? _tenantId;
  String? _role;
  String? _userId;

  KitchenOrderSync? _orderSync;
  late final KdsSettingsController _settings;

  /// Device-level preferences (reduced-motion / lite mode) from bootstrap's
  /// [AppSettingsScope]. Null in tests that build the board standalone.
  AppSettingsController? _appSettings;

  /// Reduced-motion OR lite mode — both calm the board down: 30 s timer
  /// refresh instead of 1 s ticking, no new-ticket flash, beep silenced.
  bool get _calmBoard {
    final s = _appSettings?.value;
    return s != null && (s.reducedMotion || s.liteMode);
  }

  List<KitchenTicket> _tickets = [];
  Map<String, String> _itemNames = {};
  DateTime _now = DateTime.now();

  /// Ticket ids that just arrived — their cards flash for a few seconds.
  final Map<String, DateTime> _fresh = {};

  /// Tickets already auto-advanced (the setting fires once per ticket).
  final Set<String> _autoAdvanced = {};

  StreamSubscription<List<KitchenTicket>>? _ticketsSub;
  StreamSubscription<String>? _newTicketSub;
  StreamSubscription<KitchenTransitionConflict>? _conflictSub;
  StreamSubscription<MenuDraftDoc>? _draftSub;
  Timer? _tick;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = ServicesScope.of(context);
    final session = SessionScope.maybeOf(context);
    _role = session?.role;
    _userId = session?.userId;
    final tenantId = session?.tenantId ?? 'demo-tenant';

    if (!_coreInitialized) {
      _coreInitialized = true;
      _settings = KdsSettingsController(KdsSettingsStore(services.db));
      _resetTick();
      WidgetsBinding.instance.addObserver(this);
    }
    // Device preferences can flip at runtime (Paramètres screen) — the
    // AppSettingsScope notifies, didChangeDependencies re-runs, and the
    // tick timer + beep are re-applied below.
    final appSettings = AppSettingsScope.maybeOf(context);
    if (appSettings != _appSettings) {
      _appSettings?.removeListener(_onAppSettingsChanged);
      _appSettings = appSettings;
      _appSettings?.addListener(_onAppSettingsChanged);
      _applyMotionPreferences();
    }
    // The home screen widget is const, so this State survives workspace
    // switches — re-fan-in whenever the active tenant changes.
    if (tenantId != _tenantId) {
      _stopTenantSync();
      _startTenantSync(services, tenantId);
    }
  }

  /// Starts the order fan-in for [tenantId]: Realtime push + 60 s pull +
  /// foreground-resume pull. Unconfigured backend → operates from the local
  /// cache only.
  void _startTenantSync(ServicesScope services, String tenantId) {
    _tenantId = tenantId;
    _tickets = [];
    _fresh.clear();
    _autoAdvanced.clear();
    final sync = KitchenOrderSync(
      db: services.db,
      client: TchopSupabase.clientOrNull,
    );
    _orderSync = sync;
    sync.start(tenantId);
    _ticketsSub = sync.watchTickets(tenantId).listen((tickets) {
      if (mounted) setState(() => _tickets = tickets);
    });
    _newTicketSub = sync.newTickets.listen((id) {
      if (mounted) setState(() => _fresh[id] = DateTime.now());
    });
    _conflictSub = sync.conflicts.listen((conflict) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(conflict.messageFr)),
        );
      }
    });

    // Item names for the ticket lines: live from the menu draft, seeded
    // from the published snapshot so the first paint already has names.
    _draftSub = services.menuRepository.watchDraft(tenantId).listen((doc) {
      if (mounted) {
        setState(
            () => _itemNames = {for (final i in doc.items) i.id: i.name});
      }
    });
    services.orderRepository?.loadPublishedMenu(tenantId).then((menu) {
      if (mounted && menu != null) {
        setState(
            () => _itemNames = {for (final i in menu.items) i.id: i.name});
      }
    });
  }

  void _stopTenantSync() {
    _ticketsSub?.cancel();
    _newTicketSub?.cancel();
    _conflictSub?.cancel();
    _draftSub?.cancel();
    _ticketsSub = null;
    _newTicketSub = null;
    _conflictSub = null;
    _draftSub = null;
    final sync = _orderSync;
    _orderSync = null;
    if (sync != null) unawaited(sync.dispose());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Foreground resume → pull fallback, per the fan-in contract.
    if (state == AppLifecycleState.resumed) unawaited(_orderSync?.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _appSettings?.removeListener(_onAppSettingsChanged);
    _stopTenantSync();
    _settings.dispose();
    super.dispose();
  }

  void _onAppSettingsChanged() {
    if (mounted) _applyMotionPreferences();
  }

  /// Applies reduced-motion / lite-mode to the board: silences the
  /// new-ticket beep/flash and drops the ticking timer to a 30 s text
  /// refresh. Called on init, on scope re-attach, and on every toggle.
  void _applyMotionPreferences() {
    TicketAlertBeep.quiet = _calmBoard;
    _resetTick();
  }

  /// (Re)creates the single tick timer: every second normally (elapsed
  /// timers + fresh-flash expiry + auto-advance), every 30 s when the
  /// board is calmed by reduced-motion / lite mode. Auto-advance still
  /// works — it just evaluates on the coarser cadence.
  void _resetTick() {
    _tick?.cancel();
    final calm = _calmBoard;
    if (calm) _fresh.clear();
    _tick = Timer.periodic(Duration(seconds: calm ? 30 : 1), (_) {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now();
        if (calm) {
          _fresh.clear();
        } else {
          _fresh.removeWhere(
              (_, at) => _now.difference(at) > const Duration(seconds: 8));
        }
      });
      _maybeAutoAdvance();
    });
  }

  /// KDS setting: tickets sitting in "Nouveau" auto-advance to
  /// "En préparation" after 60 s (still via `order/transition`, still
  /// role-gated and offline-safe).
  void _maybeAutoAdvance() {
    if (!_settings.value.autoAdvance) return;
    final repo = ServicesScope.of(context).orderRepository;
    if (repo == null || _tenantId == null) return;
    for (final ticket in _tickets) {
      if (ticket.status != OrderStatus.accepted) continue;
      if (_autoAdvanced.contains(ticket.id)) continue;
      if (ticket.elapsed(now: _now) < const Duration(seconds: 60)) continue;
      if (!OrderPermissions.canTransitionRole(
        role: _role,
        from: OrderStatus.accepted,
        to: OrderStatus.preparing,
      )) {
        continue;
      }
      _autoAdvanced.add(ticket.id);
      unawaited(repo
          .transitionOrder(
            tenantId: _tenantId!,
            orderId: ticket.id,
            to: OrderStatus.preparing,
          )
          .then((_) {}, onError: (_) {}));
    }
  }

  /// The card's one-tap transition: first forward step the role may take.
  OrderStatus? _cardAdvance(KitchenTicket ticket) {
    final allowed = OrderPermissions.allowedFrom(_role, ticket.status);
    for (final next in const [
      OrderStatus.preparing,
      OrderStatus.ready,
      OrderStatus.pickedUp,
    ]) {
      if (allowed.contains(next)) return next;
    }
    return null;
  }

  Future<void> _advanceTicket(KitchenTicket ticket, OrderStatus to) async {
    final repo = ServicesScope.of(context).orderRepository;
    if (repo == null || _tenantId == null) return;
    try {
      await repo.transitionOrder(
        tenantId: _tenantId!,
        orderId: ticket.id,
        to: to,
      );
    } on IllegalOrderTransition {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Transition impossible — le ticket a changé.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Échec — réessayez.')));
      }
    }
  }

  void _openTicket(KitchenTicket ticket) {
    showTicketDetailSheet(
      context: context,
      ticket: ticket,
      itemNames: _itemNames,
      tenantId: _tenantId!,
      role: _role,
      userId: _userId,
      now: _now,
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = TenantBrandingScope.of(context);
    return ValueListenableBuilder<KdsSettings>(
      valueListenable: _settings,
      builder: (context, settings, _) {
        final night = settings.nightMode;
        final station = settings.stationName.isEmpty
            ? ''
            : ' · ${settings.stationName}';
        return Scaffold(
          backgroundColor: night ? Colors.black : null,
          appBar: AppBar(
            backgroundColor: night ? Colors.black : null,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: BrandLogo(
                brandName: brand.name,
                logoUrl: brand.logoUrl,
                background: brand.primary,
                radius: 18,
              ),
            ),
            title: Text('Cuisine · ${brand.name}$station',
                style: TchopTypography.titleMedium),
            actions: [
              // Head-chef fast path: 86 a dish mid-service — opens the
              // role-aware availability board (direct toggle for head
              // chef/owner/manager, "Demander épuisement" for kitchen).
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const EightySixScreen()),
                ),
                icon:
                    const Icon(Icons.block, color: TchopColors.error, size: 18),
                label: const Text('86',
                    style: TextStyle(
                        color: TchopColors.error,
                        fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'Réglages cuisine',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => _openSettings(settings),
              ),
            ],
          ),
          body: Column(
            children: [
              // Connectivity banner, driven by the sync engine's own state.
              const OfflineBanner(
                message: 'Hors ligne — les tickets se synchroniseront',
              ),
              Expanded(
                child: context.isDesktop
                    ? _desktopBoard(night)
                    : _tabbedBoard(night),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Desktop (≥ 1100 px): the three status columns share the full width.
  Widget _desktopBoard(bool night) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (status, title, color) in _columns)
            Expanded(
                child: _column(status, title, color, night)),
        ],
      ),
    );
  }

  /// Mobile / tablet: swipeable tabs, one status per tab, with live counts.
  Widget _tabbedBoard(bool night) {
    return DefaultTabController(
      length: _columns.length,
      child: Column(
        children: [
          Material(
            color:
                night ? Colors.black : Theme.of(context).colorScheme.surface,
            child: TabBar(
              labelColor: night ? Colors.white : null,
              unselectedLabelColor: night ? Colors.white60 : null,
              tabs: [
                for (final (status, title, _) in _columns)
                  Tab(
                    child: Text(
                      '$title (${_tickets.where((t) => t.status == status).length})',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final (status, title, color) in _columns)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: _column(status, title, color, night),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One status column: header with the ticket count + the ticket list.
  ///
  /// [width] is null by default — the column fills its parent (desktop
  /// [Expanded] or a tab page). Pass an explicit width for a fixed-size
  /// column (e.g. inside a horizontal scroll view).
  Widget _column(OrderStatus status, String title, Color color, bool night,
      {double? width}) {
    final tickets =
        _tickets.where((t) => t.status == status).toList();
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: night ? 64 : 38),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$title (${tickets.length})',
              style: TextStyle(
                color: night ? Colors.white : color,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: tickets.isEmpty
                ? Center(
                    child: Text(
                      'Aucun ticket',
                      style: TchopTypography.bodySmall.copyWith(
                        color: TchopColors.textSecondary,
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      for (final ticket in tickets)
                        Builder(builder: (context) {
                          final advance = _cardAdvance(ticket);
                          return TicketCard(
                            ticket: ticket,
                            itemNames: _itemNames,
                            now: _now,
                            nightMode: night,
                            // Reduced-motion / lite mode: no flash on new
                            // tickets — the card just appears.
                            highlight: _calmBoard
                                ? false
                                : _fresh.containsKey(ticket.id),
                            onTap: () => _openTicket(ticket),
                            advanceLabel: advance == null
                                ? null
                                : OrderPermissions.actionLabelFr(advance),
                            onAdvance: advance == null
                                ? null
                                : () => _advanceTicket(ticket, advance),
                          );
                        }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettings(KdsSettings current) {
    final nameController =
        TextEditingController(text: current.stationName);
    var night = current.nightMode;
    var auto = current.autoAdvance;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: TchopColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Réglages cuisine',
                    style: TchopTypography.titleMedium),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom du poste',
                    hintText: 'Ex. Grillades, Friterie…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Mode nuit cuisine'),
                  subtitle: const Text(
                      'Contraste maximal pour le service du soir'),
                  value: night,
                  onChanged: (v) => setSheetState(() => night = v),
                ),
                SwitchListTile(
                  title: const Text('Avance auto'),
                  subtitle: const Text(
                      'Les nouveaux tickets passent en préparation après 60 s'),
                  value: auto,
                  onChanged: (v) => setSheetState(() => auto = v),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: () async {
                      await _settings.update(current.copyWith(
                        stationName: nameController.text.trim(),
                        nightMode: night,
                        autoAdvance: auto,
                      ));
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    child: const Text('Enregistrer',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(nameController.dispose);
  }
}
