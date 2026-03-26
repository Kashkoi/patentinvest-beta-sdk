/// Local snapshot of daily compliance toward beta-tester requirements.
///
/// Agreement Section 1.5:
/// - Session minimum: 15 min active engagement
/// - Reports required: 1 per 15 min of engagement per session
/// - Daily max credited: 60 min
/// - Total eligible: 275 days × 60 min = 16,500 min
/// - 25% threshold (4,125 min) required for any equity
class DailyCompliance {
  final DateTime date;

  /// Total active minutes across all sessions today (raw, uncredited).
  int totalActiveMinutes;

  /// Credited minutes today (sessions meeting 15 min + report requirements).
  int creditedMinutes;

  /// Total reports submitted today.
  int reportsSubmitted;

  /// Reports required for current session (1 per 15 min of engagement).
  int reportsRequiredForSession;

  /// Current session active minutes (real-time).
  int currentSessionMinutes;

  DailyCompliance({
    required this.date,
    this.totalActiveMinutes = 0,
    this.creditedMinutes = 0,
    this.reportsSubmitted = 0,
    this.reportsRequiredForSession = 0,
    this.currentSessionMinutes = 0,
  });

  /// Session meets minimum 15-minute threshold.
  bool get currentSessionQualifies => currentSessionMinutes >= 15;

  /// Reports submitted meet requirement for current session.
  bool get meetsReportRequirement =>
      reportsRequiredForSession == 0 ||
      reportsSubmitted >= reportsRequiredForSession;

  /// Credited minutes remaining to hit daily 60-min max.
  int get creditedMinutesRemaining =>
      (60 - creditedMinutes).clamp(0, 60);

  /// True if daily 60-min cap reached.
  bool get dailyCapReached => creditedMinutes >= 60;

  /// Achievement for display: credited / 60 as percentage for today.
  double get dailyProgressPct =>
      (creditedMinutes / 60 * 100).clamp(0, 100);

  /// Legacy compatibility.
  bool get meetsTimeRequirement => creditedMinutes >= 15;
  bool get isQualifiedDay => creditedMinutes > 0 && meetsReportRequirement;

  int get reportsRemaining {
    final needed = reportsRequiredForSession - reportsSubmitted;
    return needed > 0 ? needed : 0;
  }
}
