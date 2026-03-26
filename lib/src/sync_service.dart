import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import 'event_recorder.dart';
import 'models/engagement_event.dart';

/// Batch-uploads engagement events to the backend API.
///
/// * Runs every 60 seconds.
/// * Uses exponential back-off on failure (1 s → 2 s → 4 s … 5 min cap).
/// * Queues events while offline and drains on reconnection.
class SyncService {
  SyncService({
    required this.apiBaseUrl,
    required this.eventRecorder,
    this.syncIntervalSec = 60,
    this.maxBatchSize = 200,
  });

  final String apiBaseUrl;
  final EventRecorder eventRecorder;
  final int syncIntervalSec;
  final int maxBatchSize;

  Timer? _timer;
  int _backoffAttempt = 0;
  static const _maxBackoffSec = 300; // 5 min
  bool _syncing = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: syncIntervalSec), (_) => sync());

    // Also sync when connectivity is restored.
    _connectivitySub?.cancel();
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) sync();
    });
  }

  void dispose() {
    _timer?.cancel();
    _connectivitySub?.cancel();
  }

  /// Attempt to sync un-uploaded events. Safe to call concurrently —
  /// will no-op if already running.
  Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;

    try {
      while (true) {
        final events =
            await eventRecorder.readUnsynced(limit: maxBatchSize);
        if (events.isEmpty) break;

        final ok = await _uploadBatch(events);
        if (!ok) break; // will retry on next tick / backoff
      }
    } finally {
      _syncing = false;
    }
  }

  Future<bool> _uploadBatch(List<EngagementEvent> events) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/v1/beta/events/batch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'events': events.map((e) => e.toJson()).toList(),
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await eventRecorder.markSynced(events.map((e) => e.id).toList());
        _backoffAttempt = 0;
        return true;
      } else {
        await _backoff();
        return false;
      }
    } catch (_) {
      await _backoff();
      return false;
    }
  }

  Future<void> _backoff() async {
    _backoffAttempt++;
    final delaySec =
        min(pow(2, _backoffAttempt).toInt(), _maxBackoffSec);
    await Future<void>.delayed(Duration(seconds: delaySec));
  }
}
