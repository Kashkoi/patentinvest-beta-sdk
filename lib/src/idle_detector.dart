import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

import 'models/engagement_event.dart';

/// Activity states for the idle-detection state machine.
enum ActivityState {
  active,
  possiblyIdle,
  idle,
  background,
  suspicious,
}

/// Callback signature when the activity state changes.
typedef ActivityStateCallback = void Function(
    ActivityState previous, ActivityState current);

/// Detects real vs fake/idle usage via a five-state machine.
///
/// Only [ActivityState.active] seconds count toward the 1-hour requirement.
class IdleDetector {
  IdleDetector({
    this.activeTimeoutSec = 30,
    this.idleTimeoutSec = 120,
    this.onStateChange,
  });

  final int activeTimeoutSec;
  final int idleTimeoutSec;
  final ActivityStateCallback? onStateChange;

  ActivityState _state = ActivityState.active;
  ActivityState get state => _state;

  DateTime _lastInteraction = DateTime.now();
  Timer? _timer;

  // ── Suspicious-pattern buffers ──────────────────────────────────
  final List<_TapRecord> _recentTaps = [];
  int _screenTransitionsWithoutInteraction = 0;
  DateTime? _lastScrollTime;
  bool _deviceStationary = false;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  // ── Lifecycle ───────────────────────────────────────────────────

  void start() {
    _lastInteraction = DateTime.now();
    _state = ActivityState.active;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
    _startAccelerometer();
  }

  void dispose() {
    _timer?.cancel();
    _accelSub?.cancel();
  }

  // ── Inbound signals ─────────────────────────────────────────────

  void onInteraction(EngagementEvent event) {
    _lastInteraction = DateTime.now();

    if (event.type == EngagementEventType.tap) {
      _recentTaps.add(_TapRecord(
        time: event.timestamp,
        x: event.x ?? 0,
        y: event.y ?? 0,
      ));
      if (_recentTaps.length > 30) _recentTaps.removeAt(0);
    }

    if (event.type == EngagementEventType.scroll) {
      _lastScrollTime = event.timestamp;
    }

    if (event.type == EngagementEventType.navigation) {
      // Will be reset to 0 below only if there was a real interaction
      // between the last two navigations.
    }

    // Reset transition-without-interaction counter on non-navigation events.
    if (event.type != EngagementEventType.navigation &&
        event.type != EngagementEventType.screenView) {
      _screenTransitionsWithoutInteraction = 0;
    }

    if (_state == ActivityState.idle ||
        _state == ActivityState.possiblyIdle ||
        _state == ActivityState.suspicious) {
      _transition(ActivityState.active);
    }
  }

  void onScreenTransition() {
    _screenTransitionsWithoutInteraction++;
  }

  void onBackground() => _transition(ActivityState.background);

  void onForeground() {
    _lastInteraction = DateTime.now();
    _transition(ActivityState.active);
  }

  // ── Tick ─────────────────────────────────────────────────────────

  void _tick(Timer _) {
    if (_state == ActivityState.background) return;

    final elapsed = DateTime.now().difference(_lastInteraction).inSeconds;

    if (_isSuspicious()) {
      _transition(ActivityState.suspicious);
    } else if (elapsed > idleTimeoutSec) {
      _transition(ActivityState.idle);
    } else if (elapsed > activeTimeoutSec) {
      _transition(ActivityState.possiblyIdle);
    } else {
      if (_state != ActivityState.active) {
        _transition(ActivityState.active);
      }
    }
  }

  // ── Suspicious-pattern detection ────────────────────────────────

  bool _isSuspicious() {
    if (_hasPeriodicTaps()) return true;
    if (_hasSameCoordinateTaps()) return true;
    if (_hasNoScrollForTooLong()) return true;
    if (_hasTransitionsWithoutInteraction()) return true;
    if (_hasStationaryDeviceWithTaps()) return true;
    return false;
  }

  /// Perfectly periodic taps: same interval +/- 50 ms for > 10 events.
  bool _hasPeriodicTaps() {
    if (_recentTaps.length < 12) return false;
    final recent = _recentTaps.sublist(_recentTaps.length - 12);
    final intervals = <int>[];
    for (var i = 1; i < recent.length; i++) {
      intervals
          .add(recent[i].time.difference(recent[i - 1].time).inMilliseconds);
    }
    if (intervals.isEmpty) return false;
    final avg = intervals.reduce((a, b) => a + b) / intervals.length;
    return intervals.every((iv) => (iv - avg).abs() < 50);
  }

  /// Taps always at exact same coordinates.
  bool _hasSameCoordinateTaps() {
    if (_recentTaps.length < 10) return false;
    final recent = _recentTaps.sublist(_recentTaps.length - 10);
    final first = recent.first;
    return recent.every(
        (t) => (t.x - first.x).abs() < 2 && (t.y - first.y).abs() < 2);
  }

  /// No scroll events mixed with taps for > 5 minutes.
  bool _hasNoScrollForTooLong() {
    if (_recentTaps.length < 5) return false;
    if (_lastScrollTime == null) {
      // Never scrolled — suspicious if we have 5+ min of taps.
      final oldest = _recentTaps.first.time;
      return DateTime.now().difference(oldest).inMinutes >= 5;
    }
    return DateTime.now().difference(_lastScrollTime!).inMinutes >= 5 &&
        _recentTaps.length >= 5;
  }

  /// Screen transitions without any interaction events between them.
  bool _hasTransitionsWithoutInteraction() =>
      _screenTransitionsWithoutInteraction >= 3;

  /// Device stationary while taps are being registered.
  bool _hasStationaryDeviceWithTaps() =>
      _deviceStationary && _recentTaps.isNotEmpty &&
      DateTime.now().difference(_recentTaps.last.time).inSeconds < 5;

  // ── Accelerometer monitoring ────────────────────────────────────

  void _startAccelerometer() {
    _accelSub?.cancel();
    final samples = <double>[];
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 500),
    ).listen((event) {
      final magnitude =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      samples.add(magnitude);
      if (samples.length > 20) samples.removeAt(0);
      if (samples.length >= 10) {
        final avg = samples.reduce((a, b) => a + b) / samples.length;
        // Variance near zero → device on a table.
        final variance =
            samples.map((s) => (s - avg) * (s - avg)).reduce((a, b) => a + b) /
                samples.length;
        _deviceStationary = variance < 0.05;
      }
    });
  }

  // ── Helpers ─────────────────────────────────────────────────────

  void _transition(ActivityState next) {
    if (next == _state) return;
    final prev = _state;
    _state = next;
    onStateChange?.call(prev, next);
  }
}

class _TapRecord {
  final DateTime time;
  final double x;
  final double y;
  const _TapRecord({required this.time, required this.x, required this.y});
}
