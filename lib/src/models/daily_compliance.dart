/// Local snapshot of daily compliance toward beta-tester requirements.
class DailyCompliance {
  final DateTime date;
  int totalActiveMinutes;
  int reportsSubmitted;

  DailyCompliance({
    required this.date,
    this.totalActiveMinutes = 0,
    this.reportsSubmitted = 0,
  });

  bool get meetsTimeRequirement => totalActiveMinutes >= 60;
  bool get meetsReportRequirement => reportsSubmitted >= 5;
  bool get isQualifiedDay => meetsTimeRequirement && meetsReportRequirement;

  int get activeMinutesRemaining =>
      meetsTimeRequirement ? 0 : 60 - totalActiveMinutes;
  int get reportsRemaining =>
      meetsReportRequirement ? 0 : 5 - reportsSubmitted;
}
