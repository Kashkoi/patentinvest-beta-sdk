import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Handles incoming deep links for referral code capture.
///
/// Deep link format: https://join.patentinvest.com/r/PIH-XXXXX
///
/// On app launch:
///   1. Check for pending deep link (initial or deferred)
///   2. Extract referral code from the URI path
///   3. Store securely in local storage
///   4. Expose for pre-populating the registration screen
///   5. On registration, POST to backend to record the referral
class DeepLinkHandler {
  DeepLinkHandler({required this.apiBaseUrl});

  final String apiBaseUrl;

  final AppLinks _appLinks = AppLinks();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _storageKey = 'pending_referral_code';
  static const _referralPathPrefix = '/r/';

  StreamSubscription<Uri>? _linkSub;
  String? _pendingCode;

  /// The currently captured referral code (null if none).
  String? get pendingCode => _pendingCode;

  /// Initialize deep link listening. Call once at app startup.
  Future<void> initialize() async {
    // 1. Check for code already stored from a previous deferred link.
    _pendingCode = await _storage.read(key: _storageKey);

    // 2. Check the initial (cold-start) link.
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleUri(initialUri);
      }
    } catch (_) {
      // No initial link — fine.
    }

    // 3. Listen for links while app is running (warm-start).
    _linkSub = _appLinks.uriLinkStream.listen(_handleUri);
  }

  void dispose() {
    _linkSub?.cancel();
  }

  void _handleUri(Uri uri) {
    final code = extractCode(uri);
    if (code != null) {
      _pendingCode = code;
      _storage.write(key: _storageKey, value: code);
      debugPrint('[BetaSDK] Referral code captured: $code');
    }
  }

  /// Extract a PIH-XXXXX code from a deep link URI.
  /// Supports:
  ///   - https://join.patentinvest.com/r/PIH-A3B7K
  ///   - patentinvest://referral?code=PIH-A3B7K
  static String? extractCode(Uri uri) {
    // Path-based: /r/PIH-XXXXX
    if (uri.path.startsWith(_referralPathPrefix)) {
      final code = uri.path.substring(_referralPathPrefix.length).trim();
      if (_isValidCode(code)) return code;
    }

    // Query-based: ?code=PIH-XXXXX
    final queryCode = uri.queryParameters['code'];
    if (queryCode != null && _isValidCode(queryCode)) return queryCode;

    return null;
  }

  static bool _isValidCode(String code) {
    return RegExp(r'^PIH-[A-Z2-9]{5}$').hasMatch(code);
  }

  /// Submit the captured referral code during user registration.
  /// Call this after the user completes sign-up.
  Future<bool> submitReferral({
    required String newUserId,
    required String appId,
    String? email,
    String? deviceFingerprint,
  }) async {
    final code = _pendingCode;
    if (code == null) return false;

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/v1/ambassador/register-referral'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'referral_code': code,
          'new_user_id': newUserId,
          'app_id': appId,
          if (email != null) 'email': email,
          if (deviceFingerprint != null) 'device_fingerprint': deviceFingerprint,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await clearPendingCode();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Manually set a referral code (for the manual-entry fallback).
  Future<void> setManualCode(String code) async {
    if (_isValidCode(code)) {
      _pendingCode = code;
      await _storage.write(key: _storageKey, value: code);
    }
  }

  /// Clear the stored code after successful registration.
  Future<void> clearPendingCode() async {
    _pendingCode = null;
    await _storage.delete(key: _storageKey);
  }
}
