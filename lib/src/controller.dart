import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'current_telemetry.dart';

class BatteryController extends ChangeNotifier {
  static const channel = MethodChannel('fittery/battery');
  static const events = EventChannel('fittery/readings');
  static const previewEvents = EventChannel('fittery/preview');
  static const networkEvents = EventChannel('fittery/network');
  static const currentEvents = EventChannel('fittery/current');
  final currentTelemetry = CurrentTelemetry();
  final historyPoints = ValueNotifier<List<Map<String, dynamic>>>([]);
  final historyChanges = ChangeNotifier();
  int _telemetryHistorySeconds = 5;
  StreamSubscription<dynamic>? _currentSubscription;
  Future<void> _currentTail = Future<void>.value();
  bool _currentVisible = false,
      _currentRequested = false,
      _currentHistoryBusy = false;
  int _currentGeneration = 0;
  int? _currentHydratedUntil;
  int _currentHistoryRevision = 0;
  Reading? reading;
  Reading? network;
  final networkChanges = ChangeNotifier();
  Reading? deviceInfo;
  String? networkError, deviceInfoError;
  Map<String, dynamic> settings = {...defaults};
  Map<String, dynamic> appInfo = {};
  Map<String, dynamic>? sessionPrompt;
  List<Map<String, dynamic>> points = [], sessions = [], daily = [];
  List<Map<String, dynamic>> recordings = [];
  int? recordingsSince, recordingsUntil;
  bool moreRecordings = false;
  int _recordingsGeneration = 0;
  String? _recordingsFilter;
  bool get appActive => _appActive;
  bool _chargingDashboardVisible = false;
  bool get chargingDashboardVisible => _chargingDashboardVisible;
  bool monitoring = false, optimized = false, notificationsAllowed = false;
  bool ready = false;
  bool onboardingCompleted = false, showOnboardingOnLaunch = true;
  bool onboardingVisible = false;
  bool get shouldShowOnboarding =>
      !onboardingCompleted || showOnboardingOnLaunch;
  bool previewPlaying = false, previewBusy = false;
  String? previewEvent;
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
  bool _legacyTelemetryVisible = false;
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

  Future<void> connect({bool readingsOnly = false}) async {
    if (reading == null || _connected || _disposed) return;
    try {
      if (!readingsOnly) _connectPreview();
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
      if (readingsOnly) return;
      _syncNetwork();
      _syncCurrent();
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
    _syncCurrent();
    _restartHistoryTimer();
    if (active && (_historyVisible || _legacyTelemetryVisible)) {
      unawaited(_refreshSafely());
    }
  }

  void setDashboardVisible(bool visible) {
    if (_dashboardVisible == visible) return;
    _dashboardVisible = visible;
    _syncNetwork();
    if (visible && _connected) unawaited(loadDeviceInfo());
  }

  void setChargingDashboardVisible(bool visible) {
    if (_chargingDashboardVisible == visible) return;
    _chargingDashboardVisible = visible;
    _syncNetwork();
    _syncCurrent();
    _restartHistoryTimer();
    if (!_disposed) notifyListeners();
  }

  bool get _wantsNetwork =>
      !_disposed &&
      _connected &&
      _appActive &&
      !chargingDashboardVisible &&
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

  void setTelemetryVisible(
    bool visible, {
    bool needsHistory = true,
    int historySeconds = 5,
  }) {
    _telemetryVisible = visible;
    _legacyTelemetryVisible = visible && needsHistory;
    _telemetryHistorySeconds = historySeconds;
    _syncNetwork();
    _restartHistoryTimer();
    if (_legacyTelemetryVisible && _appActive) unawaited(_refreshSafely());
  }

  void setCurrentChartVisible(bool visible) {
    if (_disposed || _currentVisible == visible) return;
    _currentVisible = visible;
    if (visible && currentTelemetry.length == 0 && points.isNotEmpty) {
      currentTelemetry.mergeHistory(points);
    }
    _syncCurrent();
  }

  bool get _wantsCurrent =>
      !_disposed &&
      _connected &&
      _appActive &&
      _currentVisible &&
      !chargingDashboardVisible;
  void _syncCurrent() {
    final shouldRun = _wantsCurrent;
    if (shouldRun == _currentRequested) return;
    _currentRequested = shouldRun;
    currentTelemetry.setActive(shouldRun);
    if (!shouldRun) _currentGeneration++;
    _currentTail = _currentTail.then((_) async {
      if (!shouldRun) {
        final previous = _currentSubscription;
        _currentSubscription = null;
        await previous?.cancel();
        return;
      }
      if (!_wantsCurrent || _currentSubscription != null) return;
      final generation = ++_currentGeneration;
      _currentSubscription = currentEvents.receiveBroadcastStream().listen(
        (event) {
          if (_wantsCurrent && generation == _currentGeneration) {
            currentTelemetry.ingest(Map<dynamic, dynamic>.from(event as Map));
          }
        },
        onError: (Object error) {
          if (_wantsCurrent && generation == _currentGeneration) {
            currentTelemetry.reportError(
              'Live current readings stopped. Reopen this chart to retry.',
            );
          }
        },
      );
      unawaited(refreshCurrentHistory());
    });
  }

  Future<void> refreshCurrentHistory() async {
    if (_disposed || _currentHistoryBusy) return;
    _currentHistoryBusy = true;
    currentTelemetry.loading = true;
    final requestedAt = DateTime.now().millisecondsSinceEpoch;
    final revision = _currentHistoryRevision;
    try {
      final rows = await channel.invokeListMethod<dynamic>('currentHistory', {
        'since': _currentHydratedUntil == null
            ? null
            : _currentHydratedUntil! - 30000,
      });
      if (_disposed || revision != _currentHistoryRevision) return;
      if (rows == null) throw const FormatException('Missing recorded current');
      currentTelemetry.mergeHistory(
        rows.map((row) => Map<dynamic, dynamic>.from(row as Map)),
      );
      _currentHydratedUntil = requestedAt;
      currentTelemetry.reportError(null);
    } catch (_) {
      if (!_disposed) {
        currentTelemetry.reportError(
          'Saved current readings could not load. Live readings continue.',
        );
      }
    } finally {
      _currentHistoryBusy = false;
      if (!_disposed) {
        currentTelemetry.loading = false;
        currentTelemetry.notifyListeners();
      }
    }
  }

  void _restartHistoryTimer() {
    _historyTimer?.cancel();
    if (!_connected || !_appActive || _disposed || chargingDashboardVisible) {
      return;
    }
    if (_telemetryVisible && !_legacyTelemetryVisible && !_historyVisible) {
      return;
    }
    _historyTimer = Timer.periodic(
      Duration(
        seconds: _legacyTelemetryVisible
            ? _telemetryHistorySeconds
            : _historyVisible
            ? 5
            : 30,
      ),
      (_) => _refreshSafely(),
    );
  }

  void _connectPreview() {
    _previewSubscription ??= previewEvents.receiveBroadcastStream().listen(
      (event) {
        if (_disposed) return;
        previewPlaying = event == true;
        if (!previewPlaying) previewEvent = null;
        notifyListeners();
      },
      onError: (Object e) {
        if (_disposed) return;
        previewPlaying = false;
        previewEvent = null;
        notifyListeners();
      },
    );
  }

  Future<void> togglePreview([String event = 'charge']) async {
    if (previewBusy || _disposed) return;
    _connectPreview();
    previewBusy = true;
    final starting = !previewPlaying || previewEvent != event;
    notifyListeners();
    try {
      final playing = await channel.invokeMethod<bool>(
        starting ? 'previewAlarm' : 'stopPreview',
        starting ? {'event': event} : null,
      );
      if (_disposed) return;
      previewPlaying = playing == true;
      previewEvent = previewPlaying ? event : null;
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
    if (data['onboarding'] is Map) {
      _acceptOnboarding(Map<String, dynamic>.from(data['onboarding'] as Map));
    }
    monitoring = data['monitoring'] == true;
    optimized = data['optimized'] == true;
    notificationsAllowed = data['notificationsAllowed'] == true;
    sessionPrompt = data['sessionPrompt'] is Map
        ? Map<String, dynamic>.from(data['sessionPrompt'] as Map)
        : null;
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
    if (!historyLoaded) historyChanges.notifyListeners();
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
      historyPoints.value = nextPoints;
      sessions = nextSessions;
      daily = nextDaily;
      if (!_telemetryVisible) await refreshRecordings();
      if (_disposed) return;
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
      if (!_disposed) historyChanges.notifyListeners();
    }
  }

  Future<void> save(String key, dynamic value) {
    // Merge after the previous save completes so quick changes cannot replace
    // each other's values with an older copy of the settings map.
    final operation = _settingsTail.then((_) async {
      final next = {
        ...settings,
        key: value,
        if (key == 'chargingDashboard' && value == false)
          'chargingScreenSaver': false,
        if (key == 'chargingScreenSaver' && value == true)
          'chargingDashboard': true,
      };
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
    await setMonitoring(!monitoring);
  }

  void _acceptOnboarding(Map<String, dynamic> state) {
    if (state['onboardingCompleted'] is bool &&
        state['showOnboardingOnLaunch'] is bool) {
      onboardingCompleted = state['onboardingCompleted'] as bool;
      showOnboardingOnLaunch = state['showOnboardingOnLaunch'] as bool;
    }
  }

  Future<void> completeOnboarding({required bool dontShowAgain}) async {
    final state = await channel.invokeMapMethod<String, dynamic>(
      'completeOnboarding',
      {'showOnLaunch': !dontShowAgain},
    );
    if (state == null ||
        state['onboardingCompleted'] != true ||
        state['showOnboardingOnLaunch'] != !dontShowAgain) {
      throw const FormatException(
        'Your welcome preference could not be saved. Please try again.',
      );
    }
    if (_disposed) return;
    _acceptOnboarding(state);
    notifyListeners();
  }

  void setOnboardingVisible(bool visible) {
    if (_disposed) return;
    onboardingVisible = visible;
    if (!visible) {
      scheduleMicrotask(() {
        if (!_disposed) notifyListeners();
      });
    }
  }

  Future<void> setMonitoring(bool enabled) async {
    await channel.invokeMethod<void>('monitoring', enabled);
    final data = await channel.invokeMapMethod<String, dynamic>('initial');
    if (data != null) _accept(data);
    notifyListeners();
    await refreshHistory();
  }

  Future<void> dismissSessionPrompt(num token) async {
    if (sessionPrompt?['token'] == token) sessionPrompt = null;
    await channel.invokeMethod<void>('dismissSessionPrompt', token);
  }

  Future<void> refreshRecordings({bool more = false}) async {
    final filter = '$recordingsSince/$recordingsUntil';
    final filterChanged = filter != _recordingsFilter;
    final previous = filterChanged ? <Map<String, dynamic>>[] : recordings;
    _recordingsFilter = filter;
    final generation = ++_recordingsGeneration;
    final data = await channel.invokeMapMethod<String, dynamic>('recordings', {
      'since': recordingsSince,
      'until': recordingsUntil,
      'before': more && previous.isNotEmpty ? previous.last['id'] : null,
    });
    if (_disposed || generation != _recordingsGeneration) return;
    final rows = (data?['recordings'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (more) {
      final byId = {
        for (final r in [...previous, ...rows]) r['id']: r,
      };
      recordings = byId.values.toList();
      moreRecordings = data?['hasMore'] == true;
    } else {
      // Refresh the newest page without collapsing pages the user has opened.
      final oldestNew = rows.isEmpty ? null : (rows.last['id'] as num).toInt();
      final expiry = DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;
      final older = previous.length > 50 && oldestNew != null
          ? previous
                .where(
                  (r) =>
                      (r['id'] as num) < oldestNew &&
                      (flag('keepRecordings') ||
                          r['active'] == 1 ||
                          (r['startTime'] as num) > expiry),
                )
                .toList()
          : <Map<String, dynamic>>[];
      recordings = [...rows, ...older];
      moreRecordings = older.isEmpty
          ? (data?['hasMore'] == true)
          : moreRecordings;
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> recordingDetail(
    int id, {
    int? since,
    int? until,
  }) async {
    final data = await channel.invokeMapMethod<String, dynamic>(
      'recordingDetail',
      {'id': id, 'since': since, 'until': until},
    );
    if (data == null) {
      throw const FormatException('Recording could not be loaded.');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<void> renameRecording(int id, String name) async {
    await channel.invokeMethod<void>('renameRecording', {
      'id': id,
      'name': name,
    });
    await refreshRecordings();
  }

  Future<void> deleteRecording(int id) async {
    await channel.invokeMethod<void>('deleteRecording', {'id': id});
    recordings = recordings
        .where((r) => (r['id'] as num).toInt() != id)
        .toList();
    await refreshRecordings();
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

  Future<void> action(String method, {String? event}) async {
    await channel.invokeMethod<void>(
      method,
      event == null ? null : {'event': event},
    );
    if (const [
      'pickTone',
      'pickAudioFile',
      'defaultTone',
      'silentTone',
    ].contains(method)) {
      await loadInitial();
    }
    if (method == 'clearHistory') {
      _currentHistoryRevision++;
      _currentHydratedUntil = null;
      currentTelemetry.clear();
      await refreshHistory();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _syncNetwork();
    _syncCurrent();
    _subscription?.cancel();
    _previewSubscription?.cancel();
    _historyTimer?.cancel();
    networkChanges.dispose();
    currentTelemetry.dispose();
    historyPoints.dispose();
    historyChanges.dispose();
    super.dispose();
  }
}
