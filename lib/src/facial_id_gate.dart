import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';

/// Result of a facial-ID verification attempt.
class FacialIdResult {
  final bool verified;
  final double? confidence;
  final String? error;

  const FacialIdResult({
    required this.verified,
    this.confidence,
    this.error,
  });
}

/// Biometric + facial-template verification gate.
///
/// 1. Requires device biometric auth (fingerprint / face) via [local_auth].
/// 2. Captures a selfie frame via the front camera.
/// 3. POSTs the frame to the backend for facial-template matching.
/// 4. After 3 consecutive failures the session is locked.
class FacialIdGate {
  FacialIdGate({required this.apiBaseUrl, required this.betaTesterId});

  final String apiBaseUrl;
  final String betaTesterId;
  final LocalAuthentication _localAuth = LocalAuthentication();

  int _consecutiveFailures = 0;
  bool _locked = false;
  bool get isLocked => _locked;

  /// Run the full verification flow. Returns [FacialIdResult].
  Future<FacialIdResult> verify() async {
    if (_locked) {
      return const FacialIdResult(
        verified: false,
        error: 'Account locked after 3 failed facial ID attempts.',
      );
    }

    // Step 1: Device-level biometric
    try {
      final canAuth = await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!canAuth) {
        return const FacialIdResult(
          verified: false,
          error: 'Biometric authentication not available on this device.',
        );
      }

      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Verify your identity to start beta testing session',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (!didAuth) {
        _recordFailure();
        return const FacialIdResult(
          verified: false,
          error: 'Biometric authentication failed.',
        );
      }
    } catch (e) {
      _recordFailure();
      return FacialIdResult(verified: false, error: 'Biometric error: $e');
    }

    // Step 2: Capture selfie frame
    Uint8List? selfieBytes;
    try {
      selfieBytes = await _captureSelfie();
    } catch (e) {
      _recordFailure();
      return FacialIdResult(
          verified: false, error: 'Camera capture failed: $e');
    }

    if (selfieBytes == null) {
      _recordFailure();
      return const FacialIdResult(
          verified: false, error: 'No selfie captured.');
    }

    // Step 3: POST to backend for template matching
    try {
      final uri =
          Uri.parse('$apiBaseUrl/api/v1/beta/facial-verify');
      final request = http.MultipartRequest('POST', uri)
        ..fields['beta_tester_id'] = betaTesterId
        ..files.add(http.MultipartFile.fromBytes(
          'selfie',
          selfieBytes,
          filename: 'selfie.jpg',
        ));

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final verified = data['verified'] as bool? ?? false;
        final confidence = (data['confidence'] as num?)?.toDouble();

        if (verified) {
          _consecutiveFailures = 0;
          return FacialIdResult(verified: true, confidence: confidence);
        } else {
          _recordFailure();
          return FacialIdResult(
            verified: false,
            confidence: confidence,
            error: 'Facial template mismatch.',
          );
        }
      } else {
        _recordFailure();
        return FacialIdResult(
            verified: false, error: 'Server error: ${response.statusCode}');
      }
    } catch (e) {
      _recordFailure();
      return FacialIdResult(
          verified: false, error: 'Network error during facial verify: $e');
    }
  }

  void _recordFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= 3) {
      _locked = true;
      _notifyAccountLock();
    }
  }

  Future<void> _notifyAccountLock() async {
    try {
      await http.post(
        Uri.parse('$apiBaseUrl/api/v1/beta/account-lock'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'beta_tester_id': betaTesterId,
          'reason': 'facial_id_3_failures',
        }),
      );
    } catch (_) {
      // Best-effort — lock is enforced client-side regardless.
    }
  }

  Future<Uint8List?> _captureSelfie() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    final controller = CameraController(front, ResolutionPreset.medium);
    try {
      await controller.initialize();
      final xFile = await controller.takePicture();
      return await xFile.readAsBytes();
    } finally {
      await controller.dispose();
    }
  }
}
