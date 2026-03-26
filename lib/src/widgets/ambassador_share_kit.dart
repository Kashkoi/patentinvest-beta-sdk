import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

/// Ambassador sharing toolkit widget.
///
/// Displays:
///  - Referral code prominently with copy button
///  - QR code encoding the deep link
///  - Share button (native share sheet)
///  - Real-time active-user counter
///  - Progress bar toward 2,500 goal with milestones
class AmbassadorShareKit extends StatefulWidget {
  const AmbassadorShareKit({
    super.key,
    required this.referralCode,
    required this.appName,
    required this.apiBaseUrl,
    required this.testerId,
    this.goal = 2500,
    this.deepLinkDomain = 'join.patentinvest.com',
  });

  final String referralCode;
  final String appName;
  final String apiBaseUrl;
  final String testerId;
  final int goal;
  final String deepLinkDomain;

  @override
  State<AmbassadorShareKit> createState() => _AmbassadorShareKitState();
}

class _AmbassadorShareKitState extends State<AmbassadorShareKit> {
  int _activeReferrals = 0;
  int _totalReferrals = 0;
  bool _loading = true;
  final GlobalKey _socialCardKey = GlobalKey();

  String get _deepLink =>
      'https://${widget.deepLinkDomain}/r/${widget.referralCode}';

  @override
  void initState() {
    super.initState();
    _fetchReferralCounts();
  }

  Future<void> _fetchReferralCounts() async {
    try {
      final resp = await http.get(Uri.parse(
        '${widget.apiBaseUrl}/api/v1/ambassador/referrals?tester_id=${widget.testerId}',
      ));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        setState(() {
          _totalReferrals = list.length;
          _activeReferrals =
              list.where((r) => r['qualified_as_active'] == true).length;
          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.referralCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Referral code copied!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareCode() {
    final message =
        'Check out ${widget.appName}! Use my code ${widget.referralCode} '
        'when you sign up.\n$_deepLink';
    Share.share(message, subject: 'Join ${widget.appName}');
  }

  Future<void> _shareSocialCard() async {
    try {
      final boundary = _socialCardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ambassador_card.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Join ${widget.appName} with my code ${widget.referralCode}!',
      );
    } catch (_) {
      _shareCode(); // fallback to text share
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _activeReferrals / widget.goal;
    final milestones = [
      widget.goal ~/ 4,
      widget.goal ~/ 2,
      (widget.goal * 3) ~/ 4,
      widget.goal,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Referral Code Card ──────────────────────────────────
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    'Your Referral Code',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _copyCode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.referralCode,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.copy,
                              color: theme.colorScheme.onPrimaryContainer),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to copy',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── QR Code ────────────────────────────────────────────
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text('Scan to Join',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  QrImageView(
                    data: _deepLink,
                    version: QrVersions.auto,
                    size: 180,
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.circle,
                      color: theme.colorScheme.primary,
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.circle,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _deepLink,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Share Buttons ──────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _shareCode,
                  icon: const Icon(Icons.share),
                  label: const Text('Share Link'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _shareSocialCard,
                  icon: const Icon(Icons.image),
                  label: const Text('Share Card'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Progress Section ───────────────────────────────────
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Referral Progress',
                          style: theme.textTheme.titleSmall),
                      if (_loading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Counter
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '$_activeReferrals',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        TextSpan(
                          text: ' / ${widget.goal} active users',
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$_totalReferrals total sign-ups',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),

                  // Progress bar with milestones
                  _MilestoneProgressBar(
                    progress: progress.clamp(0.0, 1.0),
                    milestones: milestones,
                    current: _activeReferrals,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Social Card (hidden, used for screenshot sharing) ──
          Offstage(
            child: RepaintBoundary(
              key: _socialCardKey,
              child: _SocialCard(
                referralCode: widget.referralCode,
                appName: widget.appName,
                deepLink: _deepLink,
                activeReferrals: _activeReferrals,
                goal: widget.goal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Milestone Progress Bar ────────────────────────────────────────────

class _MilestoneProgressBar extends StatelessWidget {
  const _MilestoneProgressBar({
    required this.progress,
    required this.milestones,
    required this.current,
    required this.color,
  });

  final double progress;
  final List<int> milestones;
  final int current;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 32,
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final width = constraints.maxWidth;
              final goal = milestones.last;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Track
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  // Fill
                  Positioned(
                    top: 12,
                    left: 0,
                    child: Container(
                      height: 8,
                      width: width * progress,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  // Milestone markers
                  for (final m in milestones)
                    Positioned(
                      left: (m / goal) * width - 6,
                      top: 8,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: current >= m ? color : Colors.grey.shade300,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: milestones
              .map((m) => Text(
                    m >= 1000 ? '${(m / 1000).toStringAsFixed(1)}k' : '$m',
                    style: TextStyle(
                      fontSize: 10,
                      color: current >= m ? color : Colors.grey,
                      fontWeight:
                          current >= m ? FontWeight.bold : FontWeight.normal,
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

// ── Social Card (for screenshot sharing) ──────────────────────────────

class _SocialCard extends StatelessWidget {
  const _SocialCard({
    required this.referralCode,
    required this.appName,
    required this.deepLink,
    required this.activeReferrals,
    required this.goal,
  });

  final String referralCode;
  final String appName;
  final String deepLink;
  final int activeReferrals;
  final int goal;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 600,
      height: 340,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1a237e), Color(0xFF0d47a1)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Join $appName',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Use my referral code:',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              referralCode,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                deepLink,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              Text(
                'PatentInvest',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
