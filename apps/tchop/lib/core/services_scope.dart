import 'package:flutter/widgets.dart';

import '../data/database/tchop_database.dart';
import '../data/sync/sync_engine.dart';
import '../features/menu/availability_broadcaster.dart';
import '../features/menu/menu_repository.dart';
import '../features/orders/order_repository.dart';

/// Provides the shared data-layer services to the widget tree.
///
/// Wired once in `bootstrap.dart` (additive — Feature 2's auth work can
/// extend this scope rather than replace it).
class ServicesScope extends InheritedWidget {
  const ServicesScope({
    super.key,
    required this.db,
    required this.syncEngine,
    required this.menuRepository,
    required this.availabilityBroadcaster,
    this.orderRepository,
    required super.child,
  });

  final TchopDatabase db;
  final SyncEngine syncEngine;
  final MenuRepository menuRepository;
  final AvailabilityBroadcaster availabilityBroadcaster;

  /// Orders feature (Feature 4). Nullable for screens constructed before
  /// bootstrap wires it — callers should fall back to building one from
  /// [db]/[syncEngine] (the edge-response hook is last-writer-wins).
  final OrderRepository? orderRepository;

  static ServicesScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServicesScope>()!;

  static ServicesScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServicesScope>();

  @override
  bool updateShouldNotify(ServicesScope oldWidget) => false;
}
