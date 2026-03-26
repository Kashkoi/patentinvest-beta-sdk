import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'models/beta_report.dart';
import 'models/daily_compliance.dart';

/// Handles submission of beta-tester feedback reports to the backend.
class ReportSubmitter {
  ReportSubmitter({
    required this.apiBaseUrl,
    required this.betaTesterId,
    required this.appId,
  });

  final String apiBaseUrl;
  final String betaTesterId;
  final String appId;

  DailyCompliance _todayCompliance = DailyCompliance(date: DateTime.now());
  DailyCompliance get todayCompliance => _todayCompliance;

  void resetDayIfNeeded() {
    final now = DateTime.now();
    if (now.day != _todayCompliance.date.day ||
        now.month != _todayCompliance.date.month ||
        now.year != _todayCompliance.date.year) {
      _todayCompliance = DailyCompliance(date: now);
    }
  }

  /// Submit a report. Returns `true` on success.
  Future<bool> submit({
    required String commentText,
    required List<String> screenshotPaths,
    required ReportCategory category,
    ReportSeverity severity = ReportSeverity.medium,
    String? sessionId,
  }) async {
    if (commentText.trim().length < 20) return false;
    if (screenshotPaths.isEmpty) return false;

    final report = BetaReport(
      id: const Uuid().v4(),
      betaTesterId: betaTesterId,
      sessionId: sessionId,
      appId: appId,
      reportDate: DateTime.now(),
      commentText: commentText.trim(),
      screenshotPaths: screenshotPaths,
      category: category,
      severity: severity,
    );

    try {
      // Build multipart request to upload screenshots + report JSON.
      final uri = Uri.parse('$apiBaseUrl/api/v1/beta/reports');
      final request = http.MultipartRequest('POST', uri)
        ..fields['report_json'] = jsonEncode(report.toJson());

      for (final path in screenshotPaths) {
        final file = File(path);
        if (await file.exists()) {
          request.files.add(await http.MultipartFile.fromPath(
            'screenshots',
            path,
          ));
        }
      }

      final response = await request.send();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        resetDayIfNeeded();
        _todayCompliance.reportsSubmitted++;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Update local active-minutes count (called by SessionManager each minute).
  void updateActiveMinutes(int totalActiveMinutes) {
    resetDayIfNeeded();
    _todayCompliance.totalActiveMinutes = totalActiveMinutes;
  }
}
