import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin persistence layer for beta tester credentials.
///
/// Uses [FlutterSecureStorage] so the tester ID survives app restarts
/// and is protected by the platform keychain / keystore.
class BetaStorage {
  BetaStorage._();

  static const _storage = FlutterSecureStorage();
  static const _keyTesterId = 'beta_tester_id';
  static const _keyAgreementNumber = 'beta_agreement_number';
  static const _keyPromptSeen = 'beta_prompt_seen';
  static const _keyApiBaseUrl = 'beta_api_base_url';

  // ── Tester ID ──────────────────────────────────────────────────────

  static Future<void> saveTesterId(String id) =>
      _storage.write(key: _keyTesterId, value: id);

  static Future<String?> getSavedTesterId() =>
      _storage.read(key: _keyTesterId);

  static Future<void> clearTesterId() =>
      _storage.delete(key: _keyTesterId);

  // ── Agreement number ───────────────────────────────────────────────

  static Future<void> saveAgreementNumber(String number) =>
      _storage.write(key: _keyAgreementNumber, value: number);

  static Future<String?> getAgreementNumber() =>
      _storage.read(key: _keyAgreementNumber);

  // ── Onboarding prompt ──────────────────────────────────────────────

  static Future<bool> hasSeenBetaPrompt() async {
    final val = await _storage.read(key: _keyPromptSeen);
    return val == 'true';
  }

  static Future<void> markBetaPromptSeen() =>
      _storage.write(key: _keyPromptSeen, value: 'true');

  // ── API Base URL (configurable) ────────────────────────────────────

  static Future<void> saveApiBaseUrl(String url) =>
      _storage.write(key: _keyApiBaseUrl, value: url);

  static Future<String?> getApiBaseUrl() =>
      _storage.read(key: _keyApiBaseUrl);
}
