/// Dispatch (Feature 6) domain models.
///
/// Pure Dart — no Flutter dependency — so the assignment heuristics, the
/// outbox payload builders and the signature encoding are unit-testable.
///
/// OUTBOX OPS (see `supabase/functions/sync/index.ts`; Feature 4's
/// `order/transition` contract is reused unchanged for the pickup/delivered
/// milestones):
/// - `delivery/assign`   — entity `delivery`, payload `{order_id, driver_id}`
///   (+ optional `dropoff_lat/lng/address` captured at assign time).
/// - `delivery/complete` — entity `delivery`, payload `{delivery_id,
///   order_id, pod_photo_url, pod_photo_pending_path, pod_lat, pod_lng,
///   signature_svg}`.
///
/// HONESTY NOTE: the local Drift `deliveries` table has no dropoff
/// columns and new Drift tables/columns cannot be generated in this
/// environment (build_runner needs the Flutter SDK). The repository
/// therefore keeps assign-time dropoff metadata in a small JSON sidecar
/// file until a real Drift migration promotes it to columns.
library;
import 'dart:math' show asin, cos, pi, sin, sqrt;

/// Outbox op names + entity for dispatch (mirror in
/// `supabase/functions/sync/index.ts`).
abstract final class DispatchOps {
  static const String entity = 'delivery';

  /// Assign a driver to a ready order. Payload: `{order_id, driver_id}`.
  static const String assign = 'delivery/assign';

  /// Persist proof of delivery. Payload: `{delivery_id, order_id,
  /// pod_photo_url, pod_photo_pending_path, pod_lat, pod_lng,
  /// signature_svg}`.
  static const String complete = 'delivery/complete';
}

/// A driver eligible for assignment, as listed by the "Assigner un livreur"
/// sheet.
class DriverCandidate {
  const DriverCandidate({
    required this.driverId,
    this.displayName,
    this.activeDeliveries = 0,
    this.lastActivityAt,
  });

  /// auth.users id of the driver.
  final String driverId;

  /// May be null — the roster cache only knows ids until a server-side
  /// staff directory exists (see `DispatchRepository.driverCandidates`).
  final String? displayName;

  /// Deliveries currently assigned and not yet delivered.
  final int activeDeliveries;

  /// Last known activity (delivery completion or GPS ping). Null = never
  /// seen active → counts as the longest idle.
  final DateTime? lastActivityAt;

  /// Short id shown when no display name is known.
  String get shortId =>
      driverId.length <= 8 ? driverId : driverId.substring(0, 8);

  String labelFr() => displayName ?? 'Livreur · $shortId';
}

/// Auto-suggest the best driver for a new assignment.
///
/// Rule: fewest active deliveries first; ties broken by longest idle
/// (oldest `lastActivityAt`; a null activity counts as "idle since
/// forever"). Final tie-break on `driverId` for determinism.
///
/// Returns null when [candidates] is empty.
DriverCandidate? suggestDriver(List<DriverCandidate> candidates) {
  if (candidates.isEmpty) return null;
  final sorted = [...candidates]..sort((a, b) {
      var cmp = a.activeDeliveries.compareTo(b.activeDeliveries);
      if (cmp != 0) return cmp;
      // Longest idle first: null (never active) sorts before any timestamp.
      final atA = a.lastActivityAt;
      final atB = b.lastActivityAt;
      if (atA == null && atB == null) {
        cmp = 0;
      } else if (atA == null) {
        cmp = -1;
      } else if (atB == null) {
        cmp = 1;
      } else {
        cmp = atA.compareTo(atB);
      }
      if (cmp != 0) return cmp;
      return a.driverId.compareTo(b.driverId);
    });
  return sorted.first;
}

/// Builds the `delivery/assign` payload. Throws [ArgumentError] on empty ids.
Map<String, Object?> buildDeliveryAssignPayload({
  required String orderId,
  required String driverId,
  double? dropoffLat,
  double? dropoffLng,
  String? dropoffAddress,
}) {
  if (orderId.isEmpty) throw ArgumentError('orderId must not be empty');
  if (driverId.isEmpty) throw ArgumentError('driverId must not be empty');
  return {
    'order_id': orderId,
    'driver_id': driverId,
    if (dropoffLat != null) 'dropoff_lat': dropoffLat,
    if (dropoffLng != null) 'dropoff_lng': dropoffLng,
    if (dropoffAddress != null && dropoffAddress.isNotEmpty)
      'dropoff_address': dropoffAddress,
  };
}

/// Builds the `delivery/complete` (proof of delivery) payload.
///
/// - [podPhotoUrl]: public Storage URL of the delivery photo, when the
///   upload succeeded.
/// - [podPhotoPendingPath]: local file path of the photo when the upload
///   could not run (offline). A background uploader retries these later
///   (TODO); the server stores null for `pod_photo_url` until then.
/// - [signatureSvg]: the customer's signature as an inline SVG document
///   (see [signatureStrokesToSvg]); the server stores it in
///   `deliveries.pod_signature_url` as a `data:image/svg+xml` URI until a
///   dedicated Storage bucket exists.
Map<String, Object?> buildDeliveryCompletePayload({
  required String deliveryId,
  required String orderId,
  String? podPhotoUrl,
  String? podPhotoPendingPath,
  double? podLat,
  double? podLng,
  required String signatureSvg,
}) {
  if (deliveryId.isEmpty) throw ArgumentError('deliveryId must not be empty');
  if (orderId.isEmpty) throw ArgumentError('orderId must not be empty');
  if (signatureSvg.isEmpty) {
    throw ArgumentError('signatureSvg must not be empty');
  }
  return {
    'delivery_id': deliveryId,
    'order_id': orderId,
    'pod_photo_url': podPhotoUrl,
    'pod_photo_pending_path': podPhotoPendingPath,
    'pod_lat': podLat,
    'pod_lng': podLng,
    'signature_svg': signatureSvg,
  };
}

/// One 2-D point of a signature stroke (pure-Dart counterpart of Flutter's
/// `Offset`, so the encoding stays unit-testable without Flutter).
class SigPoint {
  const SigPoint(this.x, this.y);

  final double x;
  final double y;

  Map<String, double> toJson() => {'x': x, 'y': y};
}

/// Encodes signature strokes (one list of points per pen-down → pen-up
/// stroke) as a compact inline SVG document.
///
/// Coordinates are rounded to 1 decimal to keep the outbox payload small.
/// Returns an empty string when [strokes] contains no drawable points.
String signatureStrokesToSvg(
  List<List<SigPoint>> strokes, {
  double width = 300,
  double height = 150,
}) {
  final paths = <String>[];
  for (final stroke in strokes) {
    final pts = stroke.where((p) => p.x.isFinite && p.y.isFinite).toList();
    if (pts.isEmpty) continue;
    final buf = StringBuffer('M${_r(pts.first.x)},${_r(pts.first.y)}');
    for (var i = 1; i < pts.length; i++) {
      buf.write(' L${_r(pts[i].x)},${_r(pts[i].y)}');
    }
    // A single tap (one point) still renders: nudge a 1px segment.
    if (pts.length == 1) buf.write(' L${_r(pts.first.x + 1)},${_r(pts.first.y)}');
    paths.add('<path d="$buf" fill="none" stroke="black" '
        'stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>');
  }
  if (paths.isEmpty) return '';
  return '<svg xmlns="http://www.w3.org/2000/svg" width="${_r(width)}" '
      'height="${_r(height)}" viewBox="0 0 ${_r(width)} ${_r(height)}">'
      '${paths.join()}</svg>';
}

String _r(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
}

/// A driver GPS fix, as published over MQTT.
///
/// Topic: `tchop/{tenant_id}/drivers/{driver_id}/pos`
/// Payload keys are exactly `{lat, lng, at, speed}` — `at` is ISO-8601 UTC,
/// `speed` is km/h (nullable when the fix has no speed).
class DriverPosition {
  const DriverPosition({
    required this.lat,
    required this.lng,
    required this.at,
    this.speedKmh,
  });

  final double lat;
  final double lng;
  final DateTime at;
  final double? speedKmh;

  Map<String, Object?> toJson() => {
        'lat': lat,
        'lng': lng,
        'at': at.toUtc().toIso8601String(),
        'speed': speedKmh,
      };

  factory DriverPosition.fromJson(Map<String, dynamic> json) =>
      DriverPosition(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        at: DateTime.parse(json['at'] as String),
        speedKmh: (json['speed'] as num?)?.toDouble(),
      );
}

/// Geography helpers for the tracking UI.
abstract final class GeoUtils {
  static const double _earthKm = 6371.0;

  /// Great-circle distance in kilometres.
  static double haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_rad(lat1)) * _cos(_rad(lat2)) * _sin(dLng / 2) * _sin(dLng / 2);
    return 2 * _earthKm * _asin(sqrt(a.clamp(0.0, 1.0)));
  }

  /// Rough ETA in minutes at [speedKmh] (default: 25 km/h — Douala
  /// intra-city average on a bike). Always surfaced to users as an
  /// *estimation*, never a promise.
  static int etaMinutes(double km, {double speedKmh = 25}) {
    if (km <= 0 || speedKmh <= 0) return 0;
    return (km / speedKmh * 60).round();
  }

  /// French ETA chip text, e.g. "≈ 12 min (estimation)".
  static String etaLabelFr(double km, {double speedKmh = 25}) {
    final m = etaMinutes(km, speedKmh: speedKmh);
    if (m < 1) return 'Arrivée imminente (estimation)';
    if (m == 1) return '≈ 1 min (estimation)';
    return '≈ $m min (estimation)';
  }

  static double _rad(double deg) => deg * pi / 180;
  static double _sin(double x) => sin(x);
  static double _cos(double x) => cos(x);
  static double _asin(double x) => asin(x);
}
