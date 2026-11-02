import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patentinvest_beta_sdk/patentinvest_beta_sdk.dart';
import 'package:patentinvest_beta_sdk/src/report_submitter.dart';
import 'package:screenshot/screenshot.dart';

EngagementTracker _tracker() {
  final t = EngagementTracker(apiBaseUrl: 'http://localhost', appId: 'test', betaTesterId: 'id', requireFacialId: false);
  t.reportSubmitter = ReportSubmitter(apiBaseUrl: 'http://localhost', betaTesterId: 'id', appId: 'test');
  t.screenshotController = ScreenshotController();
  return t;
}

Widget _page(VoidCallback onPressed) => Scaffold(body: Center(child: FilledButton(onPressed: onPressed, child: const Text('Sign in'))));

void main() {
  testWidgets('inside MaterialApp.builder, the app under the overlay still takes taps', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => BetaSdkWrapper(tracker: _tracker(), child: child!),
      home: _page(() => taps++),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Sign in'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(taps, 1);
  });

  testWidgets('wrapped around MaterialApp, as older apps do, it still lays out and takes taps', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    var taps = 0;
    await tester.pumpWidget(BetaSdkWrapper(tracker: _tracker(), child: MaterialApp(home: _page(() => taps++))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Sign in'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(taps, 1);
  });
}
