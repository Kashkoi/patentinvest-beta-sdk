import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../storage/beta_storage.dart';

/// Full-screen widget where beta testers enter their assigned PIH-BTA-XXXX ID.
///
/// Validates the format, verifies against the backend, persists the ID via
/// [BetaStorage], and calls [onComplete] with the verified tester ID (or null
/// if the user skipped).
class BetaTesterIdScreen extends StatefulWidget {
  const BetaTesterIdScreen({
    super.key,
    required this.apiBaseUrl,
    required this.appId,
    required this.onComplete,
  });

  final String apiBaseUrl;
  final String appId;
  final void Function(String? testerId) onComplete;

  @override
  State<BetaTesterIdScreen> createState() => _BetaTesterIdScreenState();
}

class _BetaTesterIdScreenState extends State<BetaTesterIdScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String? _error;
  String? _agreementNumber;
  bool _verified = false;

  static final _suffixPattern = RegExp(r'^[A-Za-z0-9]{4}$');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _fullId => 'PIH-BTA-${_controller.text.trim().toUpperCase()}';

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await http.get(
        Uri.parse(
          '${widget.apiBaseUrl}/api/v1/beta/testers/check'
          '?user_id=$_fullId&app_id=${widget.appId}',
        ),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['is_beta_tester'] == true) {
          final agreement =
              data['agreement_number'] as String? ?? _fullId;
          await BetaStorage.saveTesterId(_fullId);
          await BetaStorage.saveAgreementNumber(agreement);
          await BetaStorage.markBetaPromptSeen();

          setState(() {
            _verified = true;
            _agreementNumber = agreement;
          });
          return;
        }
      }
      setState(() => _error = 'Tester ID not found. Check your assigned number and try again.');
    } catch (e) {
      setState(() => _error = 'Could not reach the server. Check your connection.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _skip() async {
    await BetaStorage.markBetaPromptSeen();
    widget.onComplete(null);
  }

  void _continue() {
    widget.onComplete(_fullId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beta Tester Registration'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: _verified ? _buildSuccess(theme) : _buildForm(theme),
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Icon(Icons.badge_outlined, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Enter Your Beta Tester ID',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the 4-character code from your assigned tester number '
          '(e.g. if your number is PIH-BTA-A1B2, enter A1B2).',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        Form(
          key: _formKey,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(12),
                  ),
                ),
                child: Text(
                  'PIH-BTA-',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: TextFormField(
                  controller: _controller,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 4,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'A1B2',
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(12),
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || !_suffixPattern.hasMatch(value.trim())) {
                      return 'Enter 4 alphanumeric characters';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _loading ? null : _verify,
          child: _loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verify & Register'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _skip,
          child: const Text('Skip \u2014 I\'m not a beta tester'),
        ),
      ],
    );
  }

  Widget _buildSuccess(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle, size: 80, color: Colors.green.shade600),
        const SizedBox(height: 16),
        Text(
          'Welcome, Beta Tester!',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Your tester ID $_fullId has been verified.',
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        if (_agreementNumber != null) ...[
          const SizedBox(height: 4),
          Text(
            'Agreement: $_agreementNumber',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'The engagement timer will now appear in the app.\n'
          'Your daily testing sessions are tracked automatically.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _continue,
          child: const Text('Continue to App'),
        ),
      ],
    );
  }
}
