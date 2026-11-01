import 'dart:async';
import 'dart:convert';
import 'dart:math' show min, pow;

import 'package:geolocator/geolocator.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../../core/app_config.dart';
import 'dispatch_models.dart';

/// MQTT configuration for driver GPS streaming.
///
/// The broker URL resolves through [AppConfig] with two layers:
///   1. runtime override pasted in the super-admin **Configuration** screen
///      (secure storage — no rebuild, reconnects pick it up live);
///   2. `--dart-define=MQTT_BROKER_URL` build-time default.
///
/// When the effective URL is unset (or left at the documented default),
/// the app automatically uses [SimulatedGpsStream] instead of a real
/// broker — the tracking UI works against either source through the
/// common [DriverPositionStream] interface.
abstract final class MqttConfig {
  /// Documented default = "unset". `wss://demo.tchop.local/mqtt` is a
  /// placeholder that resolves nowhere; the UI labels this SIMULATION.
  static const String defaultBrokerUrl = 'wss://demo.tchop.local/mqtt';

  /// Build-time default (`--dart-define=MQTT_BROKER_URL`).
  static const String buildBrokerUrl = String.fromEnvironment(
    'MQTT_BROKER_URL',
    defaultValue: defaultBrokerUrl,
  );

  /// Effective broker URL: runtime override first, build-time fallback.
  static String get brokerUrl {
    final rt = AppConfig.current.mqttBrokerUrl;
    return rt.isNotEmpty ? rt : buildBrokerUrl;
  }

  /// True when a real broker is configured in either layer.
  static bool get isConfigured =>
      brokerUrl.isNotEmpty && brokerUrl != defaultBrokerUrl;

  /// GPS topic: `tchop/{tenant_id}/drivers/{driver_id}/pos`.
  static String topicFor({
    required String tenantId,
    required String driverId,
  }) =>
      'tchop/$tenantId/drivers/$driverId/pos';

  /// How often the driver publishes a fix.
  static const Duration publishInterval = Duration(seconds: 8);

  /// One-shot connection probe for the Configuration screen's
  /// "Tester la connexion" button. Returns true when a TCP/TLS + MQTT
  /// handshake completes within [timeout]; never throws.
  static Future<bool> testConnection(
    String brokerUrl, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (brokerUrl.isEmpty || brokerUrl == defaultBrokerUrl) return false;
    MqttServerClient? client;
    try {
      final uri = Uri.parse(brokerUrl);
      final secure = uri.scheme == 'wss' || uri.scheme == 'ssl';
      final host = uri.host.isEmpty ? brokerUrl : uri.host;
      final port = uri.hasPort ? uri.port : (secure ? 8883 : 1883);
      client = MqttServerClient.withPort(
        host,
        'tchop-probe-${DateTime.now().millisecondsSinceEpoch}',
        port,
      );
      client.logging(on: false);
      client.keepAlivePeriod = 10;
      if (uri.scheme == 'ws' || uri.scheme == 'wss') {
        client.useWebSocket = true;
        client.websocketProtocols = const ['mqtt'];
      }
      if (secure) {
        client.secure = true;
        client.onBadCertificate = (_) => false;
      }
      await client.connect().timeout(timeout);
      return client.connectionStatus?.state == MqttConnectionState.connected;
    } catch (_) {
      return false;
    } finally {
      try {
        client?.disconnect();
      } catch (_) {}
    }
  }
}

/// Common interface for driver position sources.
///
/// The customer tracking screen consumes this — it does not care whether
/// the positions come from a real MQTT broker or the demo simulator.
abstract class DriverPositionStream {
  /// Live positions (newest as they arrive).
  Stream<DriverPosition> get positions;

  /// True when this source is simulated (demo mode).
  bool get isSimulation;

  Future<void> start();
  Future<void> stop();
  void dispose();
}

/// Publishes the driver's GPS fix every 8 s to
/// `tchop/{tenant_id}/drivers/{driver_id}/pos` with payload
/// `{lat, lng, at, speed}`.
///
/// Also subscribes to the same topic so `positions` re-emits the driver's
/// own fixes (useful for the driver's own "position partagée" indicator).
///
/// Reconnects with exponential backoff (2 s → 4 s → … capped at 60 s).
///
/// ANDROID HONESTY NOTE: continuous GPS while the app is backgrounded
/// requires a native foreground service, which is NOT implemented yet.
/// Add to `android/app/src/main/AndroidManifest.xml`:
/// ```xml
/// <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
/// <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
/// <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
/// <service android:name=".DispatchForegroundService"
///          android:foregroundServiceType="location"
///          android:exported="false"/>
/// ```
/// Until that native service lands, streaming only runs while the Flutter
/// engine is alive. [ForegroundServiceHook.ensureRunning] is the documented
/// hook for it (currently a no-op with a loud log).
class MqttDispatchService implements DriverPositionStream {
  MqttDispatchService();

  MqttServerClient? _client;
  Timer? _publishTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _stopping = false;

  String? _tenantId;
  String? _driverId;

  final _controller = StreamController<DriverPosition>.broadcast();

  @override
  Stream<DriverPosition> get positions => _controller.stream;

  @override
  bool get isSimulation => false;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  /// Connects to [brokerUrl] (defaults to the effective [MqttConfig.brokerUrl]
  /// — runtime override first, `--dart-define=MQTT_BROKER_URL` fallback)
  /// and starts the 8 s publish loop. Throws [ArgumentError] when asked to
  /// connect to the unset default — use [SimulatedGpsStream] instead.
  Future<void> connect({
    String? brokerUrl,
    required String tenantId,
    required String driverId,
  }) async {
    final url = (brokerUrl ?? MqttConfig.brokerUrl).trim();
    if (url.isEmpty || url == MqttConfig.defaultBrokerUrl) {
      throw ArgumentError(
        'Broker MQTT non configuré — utilisez SimulatedGpsStream '
        '(mode SIMULATION) ou collez l’URL dans Configuration '
        '(super-admin) / passez --dart-define=MQTT_BROKER_URL=…',
      );
    }
    _tenantId = tenantId;
    _driverId = driverId;
    _stopping = false;
    await _connectOnce(url);
    _publishTimer ??=
        Timer.periodic(MqttConfig.publishInterval, (_) => _publishFix());
  }

  Future<void> _connectOnce(String brokerUrl) async {
    final uri = Uri.parse(brokerUrl);
    final secure = uri.scheme == 'wss' || uri.scheme == 'ssl';
    final host = uri.host.isEmpty ? brokerUrl : uri.host;
    final port = uri.hasPort ? uri.port : (secure ? 8883 : 1883);

    final client = MqttServerClient.withPort(
      host,
      'tchop-driver-$_driverId-${DateTime.now().millisecondsSinceEpoch}',
      port,
    );
    client.logging(on: false);
    client.keepAlivePeriod = 30;
    client.autoReconnect = false; // we run our own backoff below
    if (uri.scheme == 'ws' || uri.scheme == 'wss') {
      client.useWebSocket = true;
      client.websocketProtocols = const ['mqtt'];
    }
    if (secure) {
      client.secure = true;
      client.onBadCertificate = (_) => false;
    }
    client.onDisconnected = _onDisconnected;
    _client = client;

    try {
      await client.connect();
    } catch (_) {
      client.disconnect();
      _scheduleReconnect(brokerUrl);
      return;
    }
    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      _reconnectAttempt = 0;
      final topic = MqttConfig.topicFor(
          tenantId: _tenantId!, driverId: _driverId!);
      client.subscribe(topic, MqttQos.atMostOnce);
      client.updates?.listen(_onMessage);
    } else {
      _scheduleReconnect(brokerUrl);
    }
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final m in messages) {
      final msg = m.payload as MqttPublishMessage;
      try {
        final json = jsonDecode(
          MqttPublishPayload.bytesToStringAsString(msg.payload.message),
        ) as Map<String, dynamic>;
        if (!_controller.isClosed) {
          _controller.add(DriverPosition.fromJson(json));
        }
      } catch (_) {
        // a malformed ping never breaks the stream
      }
    }
  }

  void _onDisconnected() {
    if (_stopping) return;
    _scheduleReconnect(MqttConfig.brokerUrl);
  }

  void _scheduleReconnect(String brokerUrl) {
    if (_stopping || _reconnectTimer != null) return;
    _reconnectAttempt++;
    // 2s, 4s, 8s, … capped at 60s.
    final delayS = min(60, pow(2, _reconnectAttempt).toInt());
    _reconnectTimer = Timer(Duration(seconds: delayS), () {
      _reconnectTimer = null;
      if (!_stopping) _connectOnce(brokerUrl);
    });
  }

  Future<void> _publishFix() async {
    final client = _client;
    if (client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    Position pos;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      return; // no fix this round — the loop retries in 8 s
    }
    final fix = DriverPosition(
      lat: pos.latitude,
      lng: pos.longitude,
      at: DateTime.now(),
      speedKmh: pos.speed.isNaN ? null : pos.speed * 3.6,
    );
    final builder = MqttClientPayloadBuilder()..addString(jsonEncode(fix.toJson()));
    client.publishMessage(
      MqttConfig.topicFor(tenantId: _tenantId!, driverId: _driverId!),
      MqttQos.atMostOnce,
      builder.payload!,
    );
    if (!_controller.isClosed) _controller.add(fix);
  }

  /// Subscribes to one driver's topic (customer tracking side). The
  /// driver app itself calls [connect]; the customer app calls this.
  /// [brokerUrl] defaults to the effective [MqttConfig.brokerUrl].
  Future<void> subscribe({
    String? brokerUrl,
    required String tenantId,
    required String driverId,
  }) async {
    _tenantId = tenantId;
    _driverId = driverId;
    _stopping = false;
    await _connectOnce((brokerUrl ?? MqttConfig.brokerUrl).trim());
  }

  @override
  Future<void> start() async {
    // The driver flow calls connect()/subscribe() explicitly with its
    // tenant + driver ids; start() is a no-op alias for interface parity.
  }

  @override
  Future<void> stop() async {
    _stopping = true;
    _publishTimer?.cancel();
    _publishTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _client?.disconnect();
    _client = null;
  }

  @override
  void dispose() {
    stop();
    _controller.close();
  }
}

/// DEMO ONLY — generates a moving coordinate along a straight line between
/// two points (configurable), emitting every [step].
///
/// Used automatically when `MQTT_BROKER_URL` is unset (the default). The
/// tracking UI labels this source "SIMULATION" so nobody mistakes it for
/// live GPS.
class SimulatedGpsStream implements DriverPositionStream {
  SimulatedGpsStream({
    required this.fromLat,
    required this.fromLng,
    required this.toLat,
    required this.toLng,
    this.step = const Duration(seconds: 8),
    this.stepsPerLeg = 30,
  });

  final double fromLat;
  final double fromLng;
  final double toLat;
  final double toLng;
  final Duration step;

  /// Fixes emitted per leg before the dot turns around.
  final int stepsPerLeg;

  Timer? _timer;
  int _tick = 0;
  final _controller = StreamController<DriverPosition>.broadcast();

  @override
  Stream<DriverPosition> get positions => _controller.stream;

  @override
  bool get isSimulation => true;

  @override
  Future<void> start() async {
    if (_timer != null) return;
    _timer = Timer.periodic(step, (_) {
      _tick++;
      // Ping-pong along the segment: 0 → 1 → 0 …
      final cycle = (_tick % (2 * stepsPerLeg)) / stepsPerLeg;
      final t = cycle <= 1 ? cycle : 2 - cycle;
      final lat = fromLat + (toLat - fromLat) * t;
      final lng = fromLng + (toLng - fromLng) * t;
      final km = GeoUtils.haversineKm(fromLat, fromLng, toLat, toLng);
      final legKm = stepsPerLeg == 0 ? 0.0 : km / stepsPerLeg;
      final speedKmh =
          step.inSeconds == 0 ? 0.0 : legKm / step.inSeconds * 3600;
      if (!_controller.isClosed) {
        _controller.add(DriverPosition(
          lat: lat,
          lng: lng,
          at: DateTime.now(),
          speedKmh: speedKmh,
        ));
      }
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stop();
    _controller.close();
  }
}

/// Resolves the right [DriverPositionStream] for the current config:
/// real MQTT when the effective broker URL (runtime override pasted in
/// Configuration, else `--dart-define=MQTT_BROKER_URL`) points at a real
/// broker, otherwise the clearly-labeled [SimulatedGpsStream].
abstract final class DriverPositionSource {
  static DriverPositionStream resolve({
    required String tenantId,
    required String driverId,
    double fromLat = 4.0511, // Douala — Akwa (demo default)
    double fromLng = 9.7679,
    double toLat = 4.0483, // Douala — Bonanjo (demo default)
    double toLng = 9.6843,
  }) {
    if (MqttConfig.isConfigured) {
      return MqttDispatchService();
    }
    return SimulatedGpsStream(
      fromLat: fromLat,
      fromLng: fromLng,
      toLat: toLat,
      toLng: toLng,
    );
  }
}

/// Hook for the Android foreground service (location). NOT implemented —
/// see the manifest TODO on [MqttDispatchService]. Calling this today only
/// logs; it exists so the driver home can already call the right hook.
abstract final class ForegroundServiceHook {
  static bool _warned = false;

  static Future<void> ensureRunning() async {
    // ignore: avoid_print
    print('[dispatch] ForegroundServiceHook.ensureRunning: no native '
        'foreground service yet — MQTT streaming runs only while the app '
        'is alive. See the AndroidManifest TODO on MqttDispatchService.');
    _warned = true;
  }

  static bool get warned => _warned;
}
