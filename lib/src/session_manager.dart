import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'facial_id_gate.dart';
import 'idle_detector.dart';
import 'models/beta_session.dart';

/// Manages the lifecycle of a single beta-testing session.
///
/// * Creates a session after successful facial-ID verification.
/// * Accumulates `activeSeconds` every tick while [ActivityState.active].
/// * Ends the session on app close, 10-min continuous idle, or manual call.
/// * POSTs the session summary to the backend on end.
class SessionManager {
  SessionManager({
    required this.apiBaseUrl,
    required this.betaTesterId,
    required this.appId,
    required this.idleDetector,
    required this.facialIdGate,
  });

  final String apiBaseUrl;
  final String betaTesterId;
  final String appId;
  final IdleDetector idleDetector;
  final FacialIdGate facialIdGate;

  BetaSession? _current;
  BetaSession? get current => _current;
  bool get hasActiveSession => _current != null;

  Timer? _ticker;
  int _continuousIdleSeconds = 0;
  static const _autoEndIdleSec = 600; // 10 minutes

  /// Start a new session. Runs facial-ID gate first.
  /// Returns `null` if verification fails.
  Future<BetaSession?> startSession() async {
    if (_current != null) return _current;

    final result = await facialIdGate.verify();
    if (!result.verified) return null;

    final session = BetaSession(
      id: const Uuid().v4(),
      betaTesterId: betaTesterId,
      appId: appId,
      sessionStart: DateTime.now().toUtc(),
      facialIdVerified: true,
      facialIdConfidence: result.confidence,
      deviceInfo: _collectDeviceInfo(),
    );

    _current = session;
    _continuousIdleSeconds = 0;

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), _tick);

    return session;
  }

  /// End the current session and POST summary.
  Future<void> endSession({String? reason}) async {
    final session = _current;
    if (session == null) return;

    _ticker?.cancel();
    session.sessionEnd = DateTime.now().toUtc();
    // Agreement Section 1.5: sessions < 15 min earn no credit
    session.isValidSession = session.totalActiveSeconds >= 900; // 15 min
    if (reason != null) session.invalidationReason = reason;

    _current = null;

    await _postSessionSummary(session);
  }

  void _tick(Timer _) {
    final session = _current;
    if (session == null) return;

    session.interactionCount; // already tracked via event recorder

    switch (idleDetector.state) {
      case ActivityState.active:
        session.totalActiveSeconds++;
        _continuousIdleSeconds = 0;
      case ActivityState.possiblyIdle:
        // Still counts as active for the first 30-120 sec window.
        session.totalActiveSeconds++;
        _continuousIdleSeconds = 0;
      case ActivityState.idle:
        session.totalIdleSeconds++;
        _continuousIdleSeconds++;
      case ActivityState.background:
        session.totalIdleSeconds++;
        _continuousIdleSeconds++;
      case ActivityState.suspicious:
        session.totalIdleSeconds++;
        _continuousIdleSeconds = 0; // not idle, but not counting as active
    }

    // Auto-end after 10 min continuous idle.
    if (_continuousIdleSeconds >= _autoEndIdleSec) {
      endSession(reason: 'auto_end_10min_idle');
    }
  }

  void recordScreenTransition() {
    _current?.screenTransitions++;
    idleDetector.onScreenTransition();
  }

  void recordInteraction() {
    _current?.interactionCount++;
  }

  Future<void> _postSessionSummary(BetaSession session) async {
    try {
      await http.post(
        Uri.parse('$apiBaseUrl/api/v1/beta/sessions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(session.toJson()),
      );
    } catch (_) {
      // SyncService will retry from local buffer.
    }
  }

  Map<String, dynamic> _collectDeviceInfo() {
    return {
      'platform': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'dart_version': Platform.version,
      'locale': Platform.localeName,
    };
  }
}
