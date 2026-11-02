import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:screenshot/screenshot.dart';
import 'package:uuid/uuid.dart';

import 'event_recorder.dart';
import 'facial_id_gate.dart';
import 'idle_detector.dart';
import 'models/engagement_event.dart';
import 'report_submitter.dart';
import 'session_manager.dart';
import 'storage/beta_storage.dart';
import 'sync_service.dart';
import 'widgets/beta_status_fab.dart';
import 'widgets/report_dialog.dart';

/// Main entry-point for the PatentInvest Beta SDK.
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await BetaSDK.initialize(apiBaseUrl: '...', appId: 'aura');
///   runApp(BetaSDK.wrapApp(MyApp()));
/// }
/// ```
class BetaSDK {
  BetaSDK._();

  static EngagementTracker? _tracker;
  static EngagementTracker get tracker {
    assert(_tracker != null, 'Call BetaSDK.initialize() first');
    return _tracker!;
  }

  static bool get isActive => _tracker?.isActive ?? false;

  /// Returns the previously saved beta tester ID, or null if none is stored.
  static Future<String?> getSavedTesterId() => BetaStorage.getSavedTesterId();

  /// Initialise the SDK. Checks the backend to see if [userId] (derived from
  /// device or auth) is a registered beta tester. If not, the SDK stays
  /// dormant and imposes zero overhead on the host app.
  static Future<void> initialize({
    required String apiBaseUrl,
    required String appId,
    String? userId,
    bool requireFacialId = true,
  }) async {
    // Priority: explicit userId → saved tester ID → device UUID fallback.
    final effectiveUserId = userId ?? await BetaStorage.getSavedTesterId() ?? await _resolveUserId();

    // Check registration
    final registration = await _checkRegistration(apiBaseUrl, effectiveUserId, appId);
    if (registration == null) return; // not a beta tester — dormant

    _tracker = EngagementTracker(
      apiBaseUrl: apiBaseUrl,
      appId: appId,
      betaTesterId: registration['id'] as String,
      requireFacialId: requireFacialId,
    );
    await _tracker!.start();
  }

  /// Wraps the host [app] with the SDK overlay (gesture detector, navigator
  /// observer, lifecycle watcher, FAB).
  ///
  /// The overlay needs text direction, so call this from `MaterialApp.builder`
  /// and pass the app's [navigatorKey] so the report screen can open.
  static Widget wrapApp(Widget app, {GlobalKey<NavigatorState>? navigatorKey}) {
    if (_tracker == null) return app; // dormant — no wrapping

    return BetaSdkWrapper(tracker: _tracker!, navigatorKey: navigatorKey, child: app);
  }

  /// Navigator observer to attach to MaterialApp.navigatorObservers.
  static NavigatorObserver get navigatorObserver => _tracker?._navObserver ?? NavigatorObserver();

  static Future<String> _resolveUserId() async {
    // Fallback: use a device-stable ID. In production you'd pull from
    // shared_preferences or the app's auth layer.
    return const Uuid().v5(Namespace.url.value, 'patentinvest-device');
  }

  static Future<Map<String, dynamic>?> _checkRegistration(
    String apiBaseUrl,
    String userId,
    String appId,
  ) async {
    try {
      final resp = await http.get(
        Uri.parse('$apiBaseUrl/api/v1/beta/testers/check?user_id=$userId&app_id=$appId'),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['is_beta_tester'] == true) return data;
      }
    } catch (_) {}
    return null;
  }
}

// ── EngagementTracker (singleton-per-initialisation) ─────────────────

class EngagementTracker {
  EngagementTracker({
    required this.apiBaseUrl,
    required this.appId,
    required this.betaTesterId,
    this.requireFacialId = true,
  });

  final String apiBaseUrl;
  final String appId;
  final String betaTesterId;

  /// When false, sessions start without the biometric and selfie check.
  final bool requireFacialId;

  late final IdleDetector idleDetector;
  late final EventRecorder eventRecorder;
  late final FacialIdGate facialIdGate;
  late final SessionManager sessionManager;
  late final SyncService syncService;
  late final ReportSubmitter reportSubmitter;
  late final ScreenshotController screenshotController;

  final _BetaNavObserver _navObserver = _BetaNavObserver();

  bool _started = false;
  bool get isActive => _started;

  String? _currentScreen;

  final StreamController<int> _activeSecondsCtrl = StreamController<int>.broadcast();

  /// Stream emitting cumulative active seconds for the current day.
  Stream<int> get activeSecondsStream => _activeSecondsCtrl.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    idleDetector = IdleDetector(
      onStateChange: _onActivityStateChange,
    );

    eventRecorder = EventRecorder();
    eventRecorder.start();

    facialIdGate = FacialIdGate(
      apiBaseUrl: apiBaseUrl,
      betaTesterId: betaTesterId,
    );

    sessionManager = SessionManager(
      apiBaseUrl: apiBaseUrl,
      betaTesterId: betaTesterId,
      appId: appId,
      idleDetector: idleDetector,
      facialIdGate: facialIdGate,
      requireFacialId: requireFacialId,
    );

    syncService = SyncService(
      apiBaseUrl: apiBaseUrl,
      eventRecorder: eventRecorder,
    );
    syncService.start();

    reportSubmitter = ReportSubmitter(
      apiBaseUrl: apiBaseUrl,
      betaTesterId: betaTesterId,
      appId: appId,
    );

    screenshotController = ScreenshotController();

    _navObserver.onRouteChanged = _onRouteChanged;

    idleDetector.start();

    // Start session (facial ID gate).
    await sessionManager.startSession();
  }

  void dispose() {
    idleDetector.dispose();
    eventRecorder.dispose();
    syncService.dispose();
    _activeSecondsCtrl.close();
  }

  // ── Event ingestion from the gesture overlay ────────────────────

  void onTap(Offset position) => _record(EngagementEventType.tap, x: position.dx, y: position.dy);

  void onScroll(Offset position, double delta) => _record(
        EngagementEventType.scroll,
        x: position.dx,
        y: position.dy,
        durationMs: delta.abs().toInt(),
      );

  void onLongPress(Offset position) => _record(EngagementEventType.longPress, x: position.dx, y: position.dy);

  void onTextInput() => _record(EngagementEventType.textInput);

  void onAppLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _record(EngagementEventType.background);
        idleDetector.onBackground();
      case AppLifecycleState.resumed:
        _record(EngagementEventType.foreground);
        idleDetector.onForeground();
      case AppLifecycleState.detached:
        sessionManager.endSession(reason: 'app_detached');
    }
  }

  void _onRouteChanged(String? routeName) {
    _currentScreen = routeName;
    sessionManager.recordScreenTransition();
    _record(EngagementEventType.navigation, metadata: {'screen': routeName});
  }

  void _record(
    EngagementEventType type, {
    double? x,
    double? y,
    int? durationMs,
    Map<String, dynamic>? metadata,
  }) {
    final session = sessionManager.current;
    if (session == null) return;

    final event = EngagementEvent(
      id: const Uuid().v4(),
      sessionId: session.id,
      type: type,
      timestamp: DateTime.now().toUtc(),
      screenName: _currentScreen,
      x: x,
      y: y,
      durationMs: durationMs,
      metadata: metadata,
    );

    idleDetector.onInteraction(event);
    sessionManager.recordInteraction();
    eventRecorder.record(event);

    // Emit active seconds update.
    _activeSecondsCtrl.add(session.totalActiveSeconds);
  }

  void _onActivityStateChange(ActivityState prev, ActivityState curr) {
    if (curr == ActivityState.idle && prev != ActivityState.idle) {
      _record(EngagementEventType.idleStart);
    }
    if (prev == ActivityState.idle && curr != ActivityState.idle) {
      _record(EngagementEventType.idleEnd);
    }
  }
}

// ── Navigator observer ────────────────────────────────────────────────

class _BetaNavObserver extends NavigatorObserver {
  void Function(String?)? onRouteChanged;

  @override
  void didPush(Route route, Route? previousRoute) => onRouteChanged?.call(route.settings.name);

  @override
  void didPop(Route route, Route? previousRoute) => onRouteChanged?.call(previousRoute?.settings.name);

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) => onRouteChanged?.call(newRoute?.settings.name);
}

// ── App wrapper widget ────────────────────────────────────────────────

class BetaSdkWrapper extends StatefulWidget {
  const BetaSdkWrapper({super.key, required this.tracker, required this.child, this.navigatorKey});

  final EngagementTracker tracker;
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<BetaSdkWrapper> createState() => _BetaSdkWrapperState();
}

class _BetaSdkWrapperState extends State<BetaSdkWrapper> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Listen for keyboard / text input via raw key events.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.tracker.onAppLifecycle(state);
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      widget.tracker.onTextInput();
    }
    return false; // don't consume the event
  }

  void _openReportDialog() {
    (widget.navigatorKey?.currentState ?? Navigator.of(context)).push(MaterialPageRoute(
      builder: (_) => ReportDialog(
        reportSubmitter: widget.tracker.reportSubmitter,
        screenshotController: widget.tracker.screenshotController,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Screenshot(
      controller: widget.tracker.screenshotController,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (d) => widget.tracker.onTap(d.globalPosition),
        onLongPressStart: (d) => widget.tracker.onLongPress(d.globalPosition),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notif) {
            if (notif is ScrollUpdateNotification && notif.metrics.axis == Axis.vertical) {
              widget.tracker.onScroll(
                Offset.zero,
                notif.scrollDelta ?? 0,
              );
            }
            return false;
          },
          child: Directionality(
            textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.child,
                  BetaStatusFab(
                    reportSubmitter: widget.tracker.reportSubmitter,
                    onTap: _openReportDialog,
                    activeSecondsStream: widget.tracker.activeSecondsStream,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
