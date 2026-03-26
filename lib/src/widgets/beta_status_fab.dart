import 'dart:async';

import 'package:flutter/material.dart';

import '../models/daily_compliance.dart';
import '../report_submitter.dart';

/// Floating action button showing daily beta-testing progress.
///
/// - Green checkmark: daily goals met
/// - Yellow warning: behind pace
/// - Red alert: day almost over and goals unmet
class BetaStatusFab extends StatefulWidget {
  const BetaStatusFab({
    super.key,
    required this.reportSubmitter,
    required this.onTap,
    required this.activeSecondsStream,
  });

  final ReportSubmitter reportSubmitter;
  final VoidCallback onTap;

  /// Stream that emits the cumulative active seconds for today.
  final Stream<int> activeSecondsStream;

  @override
  State<BetaStatusFab> createState() => _BetaStatusFabState();
}

class _BetaStatusFabState extends State<BetaStatusFab> {
  late Timer _refreshTimer;
  StreamSubscription<int>? _activeSub;

  @override
  void initState() {
    super.initState();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    _activeSub = widget.activeSecondsStream.listen((seconds) {
      widget.reportSubmitter.updateActiveMinutes(seconds ~/ 60);
      _refresh();
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    _activeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.reportSubmitter.resetDayIfNeeded();
    final c = widget.reportSubmitter.todayCompliance;
    final color = _statusColor(c);
    final icon = _statusIcon(c);

    return Positioned(
      bottom: 24,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Mini stats tooltip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade900.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${c.totalActiveMinutes}/60 min',
                  style: TextStyle(
                    color: c.meetsTimeRequirement
                        ? Colors.greenAccent
                        : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${c.reportsSubmitted}/5 reports',
                  style: TextStyle(
                    color: c.meetsReportRequirement
                        ? Colors.greenAccent
                        : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'beta_status_fab',
            backgroundColor: color,
            onPressed: widget.onTap,
            child: Icon(icon, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Color _statusColor(DailyCompliance c) {
    if (c.isQualifiedDay) return Colors.green;
    final hour = DateTime.now().hour;
    if (hour >= 21) return Colors.red; // after 9 PM and not done
    if (hour >= 17) return Colors.orange; // after 5 PM — warning
    return Colors.blueGrey;
  }

  IconData _statusIcon(DailyCompliance c) {
    if (c.isQualifiedDay) return Icons.check_circle;
    final hour = DateTime.now().hour;
    if (hour >= 21) return Icons.error;
    if (hour >= 17) return Icons.warning_amber_rounded;
    return Icons.bug_report;
  }
}
