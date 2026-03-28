/// PatentInvest Beta Tester Engagement SDK.
///
/// Integrates into all PatentInvest apps to measure genuine beta-tester
/// engagement via facial-ID gating, idle detection, event recording, and
/// automated compliance scoring.
///
/// Usage:
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await BetaSDK.initialize(apiBaseUrl: 'https://api.patentinvest.com', appId: 'aura');
///   runApp(BetaSDK.wrapApp(MyApp()));
/// }
/// ```
library;

export 'src/engagement_tracker.dart' show BetaSDK, EngagementTracker;
export 'src/idle_detector.dart' show ActivityState, IdleDetector;
export 'src/session_manager.dart' show SessionManager;
export 'src/facial_id_gate.dart' show FacialIdGate, FacialIdResult;
export 'src/event_recorder.dart' show EventRecorder;
export 'src/sync_service.dart' show SyncService;
export 'src/report_submitter.dart' show ReportSubmitter;
export 'src/deep_link_handler.dart' show DeepLinkHandler;
export 'src/storage/beta_storage.dart' show BetaStorage;
export 'src/models/models.dart';
export 'src/widgets/widgets.dart';
