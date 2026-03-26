import 'dart:async';

import 'package:flutter/material.dart';

import '../models/daily_compliance.dart';
import '../report_submitter.dart';

/// Floating action button with live testing timer and daily progress.
///
/// Shows real-time session timer, credited minutes, and report count.
/// Per Agreement Section 1.5: the App includes a built-in testing time
/// counter to assist Participants in tracking their Active Engagement time.
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

class _BetaStatusFabState extends State<BetaStatusFab>
    with SingleTickerProviderStateMixin {
  late Timer _refreshTimer;
  StreamSubscription<int>? _activeSub;
  int _currentActiveSeconds = 0;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    _activeSub = widget.activeSecondsStream.listen((seconds) {
      _currentActiveSeconds = seconds;
      widget.reportSubmitter
          .updateActiveMinutes(seconds ~/ 60);
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

  String _formatTimer(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${_pad(minutes)}m ${_pad(secs)}s';
    }
    return '${_pad(minutes)}:${_pad(secs)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    widget.reportSubmitter.resetDayIfNeeded();
    final c = widget.reportSubmitter.todayCompliance;
    final color = _statusColor(c);
    final sessionMin = _currentActiveSeconds ~/ 60;
    final reportsRequired = sessionMin >= 15 ? (sessionMin ~/ 15).clamp(1, 4) : 0;

    // Update compliance with real-time session data
    c.currentSessionMinutes = sessionMin;
    c.reportsRequiredForSession = reportsRequired;

    return Positioned(
      bottom: 24,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Expanded stats panel
          if (_expanded) _buildStatsPanel(c),
          if (_expanded) const SizedBox(height: 8),

          // Timer pill + FAB row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Live timer pill
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _timerColor(c),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _currentActiveSeconds > 0
                            ? Icons.timer
                            : Icons.timer_outlined,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatTimer(_currentActiveSeconds),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Main FAB
              FloatingActionButton(
                heroTag: 'beta_status_fab',
                backgroundColor: color,
                onPressed: widget.onTap,
                child: Icon(_statusIcon(c), color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsPanel(DailyCompliance c) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            'Beta Testing Progress',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Session timer (large)
          Row(
            children: [
              Icon(
                Icons.play_circle_filled,
                color: _currentActiveSeconds > 0
                    ? Colors.greenAccent
                    : Colors.grey,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                'Session: ${_formatTimer(_currentActiveSeconds)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          // Session minimum indicator
          if (_currentActiveSeconds > 0) ...[
            const SizedBox(height: 4),
            _progressBar(
              label: 'Session min (15m)',
              current: c.currentSessionMinutes,
              target: 15,
              color: c.currentSessionQualifies
                  ? Colors.greenAccent
                  : Colors.orangeAccent,
            ),
          ],

          const Divider(color: Colors.grey, height: 16),

          // Daily credited minutes
          _progressBar(
            label: 'Credited today',
            current: c.creditedMinutes,
            target: 60,
            color: c.dailyCapReached ? Colors.greenAccent : Colors.blueAccent,
            suffix: '${c.creditedMinutes}/60 min',
          ),

          const SizedBox(height: 6),

          // Reports for current session
          _progressBar(
            label: 'Reports (this session)',
            current: c.reportsSubmitted,
            target: c.reportsRequiredForSession > 0
                ? c.reportsRequiredForSession
                : 1,
            color:
                c.meetsReportRequirement ? Colors.greenAccent : Colors.amber,
            suffix:
                '${c.reportsSubmitted}/${c.reportsRequiredForSession > 0 ? c.reportsRequiredForSession : "-"}',
          ),

          const SizedBox(height: 8),

          // Hint text
          Text(
            c.dailyCapReached
                ? 'Daily cap reached!'
                : c.currentSessionQualifies
                    ? 'Session qualifies — keep going!'
                    : _currentActiveSeconds > 0
                        ? '${15 - c.currentSessionMinutes} min to qualify session'
                        : 'Start testing to earn credit',
            style: TextStyle(
              color: c.dailyCapReached
                  ? Colors.greenAccent
                  : Colors.grey.shade400,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressBar({
    required String label,
    required int current,
    required int target,
    required Color color,
    String? suffix,
  }) {
    final pct = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
            ),
            if (suffix != null)
              Text(
                suffix,
                style: TextStyle(
                  color: Colors.grey.shade300,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.grey.shade700,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 4,
          ),
        ),
      ],
    );
  }

  Color _timerColor(DailyCompliance c) {
    if (c.dailyCapReached) return Colors.green.shade700;
    if (_currentActiveSeconds > 0 && c.currentSessionQualifies) {
      return Colors.blue.shade700;
    }
    if (_currentActiveSeconds > 0) return Colors.orange.shade700;
    return Colors.grey.shade700;
  }

  Color _statusColor(DailyCompliance c) {
    if (c.dailyCapReached) return Colors.green;
    if (c.creditedMinutes > 0) return Colors.blue;
    final hour = DateTime.now().hour;
    if (hour >= 21) return Colors.red;
    if (hour >= 17) return Colors.orange;
    return Colors.blueGrey;
  }

  IconData _statusIcon(DailyCompliance c) {
    if (c.dailyCapReached) return Icons.check_circle;
    if (c.creditedMinutes > 0) return Icons.trending_up;
    final hour = DateTime.now().hour;
    if (hour >= 21) return Icons.error;
    if (hour >= 17) return Icons.warning_amber_rounded;
    return Icons.bug_report;
  }
}
