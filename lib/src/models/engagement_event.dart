/// A single user-interaction event captured by the SDK.
class EngagementEvent {
  final String id;
  final String sessionId;
  final EngagementEventType type;
  final DateTime timestamp;
  final String? screenName;
  final double? x;
  final double? y;
  final int? durationMs;
  final Map<String, dynamic>? metadata;

  const EngagementEvent({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.timestamp,
    this.screenName,
    this.x,
    this.y,
    this.durationMs,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'session_id': sessionId,
        'event_type': type.name,
        'timestamp': timestamp.toUtc().toIso8601String(),
        if (screenName != null) 'screen_name': screenName,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (durationMs != null) 'duration_ms': durationMs,
        if (metadata != null) 'metadata': metadata,
      };

  factory EngagementEvent.fromJson(Map<String, dynamic> j) => EngagementEvent(
        id: j['id'] as String,
        sessionId: j['session_id'] as String,
        type: EngagementEventType.values.byName(j['event_type'] as String),
        timestamp: DateTime.parse(j['timestamp'] as String),
        screenName: j['screen_name'] as String?,
        x: (j['x'] as num?)?.toDouble(),
        y: (j['y'] as num?)?.toDouble(),
        durationMs: j['duration_ms'] as int?,
        metadata: j['metadata'] as Map<String, dynamic>?,
      );
}

enum EngagementEventType {
  tap,
  scroll,
  longPress,
  textInput,
  navigation,
  screenView,
  gesture,
  appLifecycle,
  idleStart,
  idleEnd,
  background,
  foreground,
}
