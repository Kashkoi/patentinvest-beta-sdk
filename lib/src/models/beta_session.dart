/// Represents a single beta-testing session bounded by facial-ID verification.
class BetaSession {
  final String id;
  final String betaTesterId;
  final String appId;
  final DateTime sessionStart;
  DateTime? sessionEnd;
  bool facialIdVerified;
  double? facialIdConfidence;
  int totalActiveSeconds;
  int totalIdleSeconds;
  int interactionCount;
  int screenTransitions;
  bool isValidSession;
  String? invalidationReason;
  Map<String, dynamic>? deviceInfo;

  BetaSession({
    required this.id,
    required this.betaTesterId,
    required this.appId,
    required this.sessionStart,
    this.sessionEnd,
    this.facialIdVerified = false,
    this.facialIdConfidence,
    this.totalActiveSeconds = 0,
    this.totalIdleSeconds = 0,
    this.interactionCount = 0,
    this.screenTransitions = 0,
    this.isValidSession = false,
    this.invalidationReason,
    this.deviceInfo,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'beta_tester_id': betaTesterId,
        'app_id': appId,
        'session_start': sessionStart.toUtc().toIso8601String(),
        'session_end': sessionEnd?.toUtc().toIso8601String(),
        'facial_id_verified': facialIdVerified,
        'facial_id_confidence': facialIdConfidence,
        'total_active_seconds': totalActiveSeconds,
        'total_idle_seconds': totalIdleSeconds,
        'interaction_count': interactionCount,
        'screen_transitions': screenTransitions,
        'is_valid_session': isValidSession,
        'invalidation_reason': invalidationReason,
        'device_info': deviceInfo,
      };
}
