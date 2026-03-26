/// A feedback report submitted by a beta tester.
class BetaReport {
  final String id;
  final String betaTesterId;
  final String? sessionId;
  final String appId;
  final DateTime reportDate;
  final String commentText;
  final List<String> screenshotPaths;
  final ReportCategory category;
  final ReportSeverity severity;

  const BetaReport({
    required this.id,
    required this.betaTesterId,
    this.sessionId,
    required this.appId,
    required this.reportDate,
    required this.commentText,
    required this.screenshotPaths,
    required this.category,
    this.severity = ReportSeverity.medium,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'beta_tester_id': betaTesterId,
        'session_id': sessionId,
        'app_id': appId,
        'report_date': reportDate.toIso8601String().split('T').first,
        'comment_text': commentText,
        'screenshot_paths': screenshotPaths,
        'category': category.name,
        'severity': severity.name,
      };
}

enum ReportCategory {
  bug,
  uxFeedback,
  featureRequest,
  performance,
  accessibility,
  general,
}

enum ReportSeverity {
  critical,
  high,
  medium,
  low,
  informational,
}
