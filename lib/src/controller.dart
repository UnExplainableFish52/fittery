import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'models.dart';

class BatteryController extends ChangeNotifier {
  static const channel = MethodChannel('fittery/battery');
  static const events = EventChannel('fittery/readings');
  static const previewEvents = EventChannel('fittery/preview');
  static const networkEvents = EventChannel('fittery/network');
  Reading? reading;
  Reading? network;
  final networkChanges = ChangeNotifier();
  Reading? deviceInfo;
  String? networkError, deviceInfoError;
  Map<String, dynamic> settings = {...defaults};
  Map<String, dynamic> appInfo = {};
  List<Map<String, dynamic>> points = [], sessions = [], daily = [];
  bool monitoring = false, optimized = false, notificationsAllowed = false;
  bool ready = false;
  bool previewPlaying = false, previewBusy = false;
  String? error;
  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<dynamic>? _previewSubscription;
  StreamSubscription<dynamic>? _networkSubscription;
  Future<void> _networkTail = Future<void>.value();
  int _networkGeneration = 0;
  bool _networkRequested = false;
  bool _dashboardVisible = true, _loadingDeviceInfo = false;
  bool _disposed = false;
  Timer? _historyTimer;
  bool _loadingHistory = false;
  bool historyLoaded = false;
  bool get historyLoading => _loadingHistory;
  DateTime? historyUpdatedAt;
  String? _historyReadError, _historyWriteError;
  String? get historyError => _historyWriteError ?? _historyReadError;
  bool _connected = false,
      _historyVisible = false,
      _telemetryVisible = false,
      _appActive = true;
  Future<void> _settingsTail = Future<void>.value();

  bool flag(String key) => settings[key] == true;
  Future<void> initialize() async {
    await loadInitial();
    await connect();
  }

  Future<void> loadInitial() async {
    try {
      final initial = await channel.invokeMapMethod<String, dynamic>('initial');
      if (initial != null) _accept(initial);
      ready = true;
      notifyListeners();
    } on MissingPluginException {
      ready = true;
      error = 'Live battery readings require the Android app.';
      notifyListeners();
    } catch (e) {
      ready = true;
      error = 'Could not connect to battery monitoring: $e';
      notifyListeners();
    }
  }

  Future<void> connect() async {
    if (reading == null || _connected || _disposed) return;
    try {
      _connectPreview();
      _subscription = events.receiveBroadcastStream().listen(
        (event) {
          _accept(Map<String, dynamic>.from(event as Map));
          notifyListeners();
        },
        onError: (Object e) {
          error = 'Battery updates stopped. Reopen the app to reconnect.';
          notifyListeners();
        },
      );
      _connected = true;
      _syncNetwork();
      unawaited(loadDeviceInfo());
      _restartHistoryTimer();
      appInfo = await channel.invokeMapMethod<String, dynamic>('appInfo') ?? {};
      await _refreshSafely();
    } catch (e) {
      ready = true;
      error = 'Could not connect to battery monitoring: $e';
      notifyListeners();
    }
  }

  void setHistoryVisible(bool visible) {
    _historyVisible = visible;
    _restartHistoryTimer();
    if (visible && _appActive) unawaited(_refreshSafely());
  }

  void setAppActive(bool active) {
    if (_appActive == active) return;
    _appActive = active;
    _syncNetwork();
    _restartHistoryTimer();
    if (active && (_historyVisible || _telemetryVisible)) {
      unawaited(_refreshSafely());
    }
  }

  void setDashboardVisible(bool visible) {
    if (_dashboardVisible == visible) return;
    _dashboardVisible = visible;
    _syncNetwork();
    if (visible && _connected) unawaited(loadDeviceInfo());
  }

  bool get _wantsNetwork =>
      !_disposed &&
      _connected &&
      _appActive &&
      _dashboardVisible &&
      !_telemetryVisible &&
      flag('networkEnabled');

  void _syncNetwork() {
    final shouldRun = _wantsNetwork;
    if (shouldRun == _networkRequested) return;
    _networkRequested = shouldRun;
    if (!shouldRun) {
      _networkGeneration++;
      network = null;
      networkError = null;
      if (!_disposed) networkChanges.notifyListeners();
    }
    // Serialize cancellation and listening so rapid tab/lifecycle changes cannot
    // leave a native observer running after its Dart subscription is cancelled.
    _networkTail = _networkTail.then((_) async {
      if (!shouldRun) {
        final previous = _networkSubscription;
        _networkSubscription = null;
        await previous?.cancel();
        return;
      }
      if (!_wantsNetwork || _networkSubscription != null) return;
      final generation = ++_networkGeneration;
      _networkSubscription = networkEvents.receiveBroadcastStream().listen(
        (event) {
          if (!_wantsNetwork || generation != _networkGeneration) return;
          network = Reading(Map<String, dynamic>.from(event as Map));
          networkError = network!.data['error'] as String?;
          networkChanges.notifyListeners();
        },
        onError: (Object error) {
          if (!_wantsNetwork || generation != _networkGeneration) return;
          network = null;
          networkError = 'Network activity is unavailable. Toggle it to retry.';
          networkChanges.notifyListeners();
        },
      );
    });
  }

  Future<void> loadDeviceInfo({bool refresh = false}) async {
    if (_disposed || _loadingDeviceInfo || (!refresh && deviceInfo != null)) {
      return;
    }
    _loadingDeviceInfo = true;
    try {
      final data = await channel.invokeMapMethod<String, dynamic>('deviceInfo');
      if (_disposed) return;
      if (data != null) deviceInfo = Reading(data);
      deviceInfoError = null;
    } catch (_) {
      if (!_disposed) {
        deviceInfoError = 'Some device information is unavailable.';
      }
    } finally {
      _loadingDeviceInfo = false;
      if (!_disposed) notifyListeners();
    }
  }

  void setTelemetryVisible(bool visible) {
    _telemetryVisible = visible;
    _syncNetwork();
    _restartHistoryTimer();
    if (visible && _appActive) unawaited(_refreshSafely());
  }

  void _restartHistoryTimer() {
    _historyTimer?.cancel();
    if (!_connected || !_appActive || _disposed) return;
    _historyTimer = Timer.periodic(
      Duration(seconds: _historyVisible || _telemetryVisible ? 5 : 30),
      (_) => _refreshSafely(),
    );
  }

  void _connectPreview() {
    _previewSubscription ??= previewEvents.receiveBroadcastStream().listen(
      (event) {
        if (_disposed) return;
        previewPlaying = event == true;
        notifyListeners();
      },
      onError: (Object e) {
        if (_disposed) return;
        previewPlaying = false;
        notifyListeners();
      },
    );
  }

  Future<void> togglePreview() async {
    if (previewBusy || _disposed) return;
    _connectPreview();
    previewBusy = true;
    final starting = !previewPlaying;
    notifyListeners();
    try {
      final playing = await channel.invokeMethod<bool>(
        starting ? 'previewAlarm' : 'stopPreview',
      );
      if (_disposed) return;
      previewPlaying = playing == true;
      if (starting && !previewPlaying) {
        throw PlatformException(
          code: 'PREVIEW',
          message: 'Choose an audible alarm tone to play a preview.',
        );
      }
    } finally {
      previewBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _refreshSafely() async {
    try {
      await refreshHistory();
    } catch (_) {
      // refreshHistory retains saved data and exposes a persistent history error.
    }
  }

  void _accept(Map<String, dynamic> data) {
    final incomingSequence = data['sequence'];
    final currentSequence = reading?.number('sequence');
    if (incomingSequence is num &&
        currentSequence != null &&
        incomingSequence < currentSequence) {
      return;
    }
    reading = Reading(data);
    monitoring = data['monitoring'] == true;
    optimized = data['optimized'] == true;
    notificationsAllowed = data['notificationsAllowed'] == true;
    _historyWriteError = data['historyError'] as String?;
    if (data['settings'] is Map) {
      settings = {
        ...defaults,
        ...Map<String, dynamic>.from(data['settings'] as Map),
      };
      _syncNetwork();
    }
    error = null;
  }

  Future<void> refreshHistory() async {
    if (_loadingHistory || _disposed) return;
    _loadingHistory = true;
    notifyListeners();
    try {
      final data = await channel.invokeMapMethod<String, dynamic>('history');
      if (_disposed) return;
      if (data == null) throw const FormatException('Missing history response');
      final nextPoints = (data['points'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final nextSessions = (data['sessions'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final nextDaily = (data['daily'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      points = nextPoints;
      sessions = nextSessions;
      daily = nextDaily;
      historyLoaded = true;
      historyUpdatedAt = DateTime.now();
      _historyReadError = null;
    } catch (_) {
      if (!_disposed) {
        _historyReadError = historyLoaded
            ? 'History could not refresh. Showing the last saved readings.'
            : 'History could not load. Pull down to retry.';
      }
      rethrow;
    } finally {
      _loadingHistory = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> save(String key, dynamic value) {
    // Merge after the previous save completes so quick changes cannot replace
    // each other's values with an older copy of the settings map.
    final operation = _settingsTail.then((_) async {
      final next = {...settings, key: value};
      await channel.invokeMethod<void>('updateSetting', {
        'key': key,
        'value': value,
      });
      settings = next;
      _syncNetwork();
      notifyListeners();
    });
    // A failed write is reported to its caller without blocking later saves.
    _settingsTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> toggleMonitoring() async {
    await channel.invokeMethod<void>('monitoring', !monitoring);
    final data = await channel.invokeMapMethod<String, dynamic>('initial');
    if (data != null) _accept(data);
    notifyListeners();
  }

  Future<void> refreshReading() async {
    final data = await channel.invokeMapMethod<String, dynamic>('refresh');
    if (data != null && !_disposed) {
      _accept(data);
      notifyListeners();
    }
    await loadDeviceInfo(refresh: true);
  }

  Future<void> openLink(String url) =>
      channel.invokeMethod<void>('openLink', url);

  Future<void> action(String method) async {
    await channel.invokeMethod<void>(method);
    if (method == 'clearHistory') await refreshHistory();
  }

  @override
  void dispose() {
    _disposed = true;
    _syncNetwork();
    _subscription?.cancel();
    _previewSubscription?.cancel();
    _historyTimer?.cancel();
    networkChanges.dispose();
    super.dispose();
  }
}
