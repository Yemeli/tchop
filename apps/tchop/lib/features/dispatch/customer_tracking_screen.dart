import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/branding/tenant_branding_scope.dart';
import '../../core/responsive.dart';
import '../../core/ui/app_settings_scope.dart';
import '../../core/ui/state_views.dart';
import '../../design_system/tchop_colors.dart';
import '../../design_system/tchop_typography.dart';
import '../orders/order_repository.dart';
import 'dispatch_models.dart';
import 'map_placeholder.dart';
import 'mqtt_dispatch_service.dart';

/// Google Maps API key, resolved through [AppConfig]: runtime override
/// pasted in the super-admin Configuration screen first,
/// `--dart-define=MAPS_API_KEY` build-time fallback.
///
/// HONEST LIMITATION — the native map view (Android/iOS) reads the key
/// from the platform manifest AT BUILD TIME, so a key pasted at runtime
/// only takes full effect for the in-app map after a rebuild. It IS usable
/// immediately for HTTP-based Maps calls (geocoding, Static Maps…).
/// When no key exists in either layer, the screen renders [MapPlaceholder].
abstract final class MapsConfig {
  static String get apiKey => AppConfig.current.mapsApiKey;

  static bool get isConfigured => apiKey.isNotEmpty;

  /// True when the key was baked in at build time (native map view works).
  static bool get isBuildTimeKey =>
      AppConfig.current.mapsApiKeySource == ConfigSource.build;
}

/// Customer live-tracking screen: restaurant pin, driver pin (updated from
/// [DriverPositionStream]), customer pin, ETA text, order status timeline
/// and a driver call button.
///
/// Works against EITHER a real MQTT broker or the [SimulatedGpsStream] —
/// the source is chosen by [DriverPositionSource.resolve] and the UI shows
/// a "SIMULATION" badge when simulated.
class CustomerTrackingScreen extends StatefulWidget {
  const CustomerTrackingScreen({
    super.key,
    required this.order,
    required this.tenantId,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.restaurantLat,
    required this.restaurantLng,
    required this.customerLat,
    required this.customerLng,
    this.positionSource,
  });

  final OrderCard order;
  final String tenantId;
  final String driverId;

  /// May be a short id when the roster has no display name yet.
  final String driverName;
  final String? driverPhone;
  final double restaurantLat;
  final double restaurantLng;
  final double customerLat;
  final double customerLng;

  /// Defaults to [DriverPositionSource.resolve] (MQTT or simulation).
  final DriverPositionStream? positionSource;

  @override
  State<CustomerTrackingScreen> createState() => _CustomerTrackingScreenState();
}

class _CustomerTrackingScreenState extends State<CustomerTrackingScreen> {
  late final DriverPositionStream _source;
  StreamSubscription<DriverPosition>? _sub;
  DriverPosition? _driverPos;
  GoogleMapController? _map;

  @override
  void initState() {
    super.initState();
    _source = widget.positionSource ??
        DriverPositionSource.resolve(
          tenantId: widget.tenantId,
          driverId: widget.driverId,
          fromLat: widget.restaurantLat,
          fromLng: widget.restaurantLng,
          toLat: widget.customerLat,
          toLng: widget.customerLng,
        );
    _boot();
  }

  Future<void> _boot() async {
    await _source.start();
    if (_source is MqttDispatchService) {
      try {
        await _source.subscribe(
          tenantId: widget.tenantId,
          driverId: widget.driverId,
        );
      } catch (_) {
        // stays on an empty stream — the placeholder-free layout still
        // shows pins + timeline
      }
    }
    _sub = _source.positions.listen((pos) {
      if (!mounted) return;
      setState(() => _driverPos = pos);
      _recenterOnDriver(pos);
    });
  }

  void _recenterOnDriver(DriverPosition pos) {
    _map?.animateCamera(CameraUpdate.newLatLng(LatLng(pos.lat, pos.lng)));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _source.stop();
    // The source is owned by this screen only when we created it.
    if (widget.positionSource == null) _source.dispose();
    super.dispose();
  }

  Future<void> _callDriver() async {
    final phone = widget.driverPhone;
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Numéro du livreur indisponible.')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de passer l’appel.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Lite mode: the live map is replaced by the list-mode placeholder
    // even when a Maps API key is configured (GPU + data savings).
    final liteMode =
        AppSettingsScope.maybeOf(context)?.value.liteMode ?? false;
    final showMap = MapsConfig.isConfigured && !liteMode;
    return Scaffold(
      appBar: AppBar(
        title: Text('Suivi · Commande ${widget.order.id.substring(0, 8)}',
            style: TchopTypography.titleMedium),
        actions: [
          if (_source.isSimulation)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Chip(label: Text('SIMULATION')),
            ),
        ],
      ),
      body: context.isDesktop
          ? _desktopBody(showMap, liteMode)
          : _mobileBody(showMap, liteMode),
    );
  }

  /// Mobile / tablet: stacked — map (or placeholder) on top, details
  /// below in a scroll view.
  Widget _mobileBody(bool showMap, bool liteMode) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const OfflineBanner(),
        _buildEtaCard(),
        const SizedBox(height: 12),
        if (showMap)
          SizedBox(height: 320, child: _buildMap())
        else
          _placeholderSection(liteMode),
        const SizedBox(height: 12),
        _buildDriverCard(),
        const SizedBox(height: 12),
        if (showMap) _timelineCard(),
      ],
    );
  }

  /// Desktop: map (or placeholder) expanded on the left, 360 px details
  /// panel on the right.
  Widget _desktopBody(bool showMap, bool liteMode) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: showMap
                ? SizedBox.expand(child: _buildMap())
                : SingleChildScrollView(
                    child: _placeholderSection(liteMode)),
          ),
        ),
        SizedBox(
          width: 360,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const OfflineBanner(),
              _buildEtaCard(),
              const SizedBox(height: 12),
              _buildDriverCard(),
              const SizedBox(height: 12),
              _timelineCard(),
            ],
          ),
        ),
      ],
    );
  }

  /// Placeholder pins + timeline, shared by both layouts when no Maps
  /// key is configured (or in lite mode).
  Widget _placeholderSection(bool liteMode) {
    final brand = TenantBrandingScope.of(context);
    final order = widget.order;
    return MapPlaceholder(
      currentStatus: order.status,
      note: liteMode
          ? 'Mode allégé — la carte est remplacée par la liste '
              'des étapes.'
          : 'Collez une clé Google Maps dans Configuration '
              '(super-admin) ou ajoutez --dart-define=MAPS_API_KEY=… '
              'au build pour activer la carte.',
      pins: [
        MapPin(
          label: 'Restaurant',
          detail: brand.name,
          color: brand.primary,
          icon: Icons.restaurant,
        ),
        MapPin(
          label: 'Livreur',
          detail: _driverPos == null
              ? widget.driverName
              : '${widget.driverName} — position reçue à '
                  '${_driverPos!.at.toLocal().hour.toString().padLeft(2, '0')}:'
                  '${_driverPos!.at.toLocal().minute.toString().padLeft(2, '0')}',
          color: TchopColors.info,
          icon: Icons.delivery_dining,
        ),
        MapPin(
          label: 'Vous',
          detail: order.address ?? 'Adresse de livraison',
          color: TchopColors.success,
          icon: Icons.home,
        ),
      ],
    );
  }

  Widget _timelineCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: OrderStatusTimeline(current: widget.order.status),
      ),
    );
  }

  Widget _buildEtaCard() {
    final pos = _driverPos;
    final String text;
    if (pos == null) {
      text = 'En attente de la position du livreur…';
    } else {
      final km = GeoUtils.haversineKm(
          pos.lat, pos.lng, widget.customerLat, widget.customerLng);
      // "estimation" label is part of the string (see GeoUtils.etaLabelFr).
      text = 'Arrivée ${GeoUtils.etaLabelFr(km)}';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.timer_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: TchopTypography.titleMedium),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    final restaurant =
        LatLng(widget.restaurantLat, widget.restaurantLng);
    final customer = LatLng(widget.customerLat, widget.customerLng);
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('restaurant'),
        position: restaurant,
        infoWindow: const InfoWindow(title: 'Restaurant'),
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ),
      Marker(
        markerId: const MarkerId('customer'),
        position: customer,
        infoWindow: const InfoWindow(title: 'Vous'),
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      if (_driverPos != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(_driverPos!.lat, _driverPos!.lng),
          infoWindow: InfoWindow(title: widget.driverName),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure),
        ),
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(
            (widget.restaurantLat + widget.customerLat) / 2,
            (widget.restaurantLng + widget.customerLng) / 2,
          ),
          zoom: 13,
        ),
        markers: markers,
        myLocationEnabled: false,
        zoomControlsEnabled: true,
        onMapCreated: (c) => _map = c,
      ),
    );
  }

  Widget _buildDriverCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.delivery_dining)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.driverName,
                      style: TchopTypography.titleMedium),
                  Text(widget.order.statusLabelFr,
                      style: TextStyle(color: TchopColors.textSecondary)),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _callDriver,
              icon: const Icon(Icons.phone),
              label: const Text('Appeler'),
            ),
          ],
        ),
      ),
    );
  }
}
