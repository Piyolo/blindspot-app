import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import '../constants/copy.dart';
import '../providers/auth_provider.dart';
import '../services/validation.dart';
import '../theme/tokens.dart';
import '../widgets/voice_field.dart';

/// How long a submit may stay in flight before the waking banner appears
/// even though no retry has fired yet (a cold Render wake measured 32.5 s
/// against the 25 s client timeout).
const Duration _wakingDelay = Duration(seconds: 5);

/// Signed-out account creation: name, email, password, confirm, contact
/// number. Client-side validation covers exactly the rules the copy deck
/// has strings for — the password rule, the confirm mismatch (same
/// copy), and the contact-number range — before anything reaches the
/// repository; the contact number is normalized to the server's
/// canonical form on the way out.
///
/// Like [LoginScreen], shows the waking banner on `auth.retryingNetwork`
/// or a submit in flight past [_wakingDelay], with the timer cancelled
/// on settle and on dispose.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _contact = TextEditingController();

  late final AuthProvider _auth;
  Timer? _wakingTimer;
  bool _pendingByTimer = false;
  bool _wakingAnnounced = false;
  String? _passwordError;
  String? _confirmError;
  String? _contactError;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _auth.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _wakingTimer?.cancel();
    _auth.removeListener(_onAuthChanged);
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _contact.dispose();
    super.dispose();
  }

  bool get _showWaking => _auth.retryingNetwork || _pendingByTimer;

  void _onAuthChanged() {
    if (!mounted) {
      return;
    }
    _syncWakingBanner();
    setState(() {});
  }

  /// Announces the waking copy exactly once per appearance of the banner
  /// (state changes are never signalled by colour or position alone).
  void _syncWakingBanner() {
    if (_showWaking && !_wakingAnnounced) {
      _wakingAnnounced = true;
      unawaited(_announce(Copy.serverWaking));
    } else if (!_showWaking) {
      _wakingAnnounced = false;
    }
  }

  /// Announces [message] as a best-effort secondary signal. The primary
  /// channel is the live region on the visible text: Android has deprecated
  /// announcement events, so TalkBack on modern Android may ignore them
  /// entirely. An announcement failure must never fail the screen action
  /// it accompanies, so errors are swallowed.
  Future<void> _announce(String message) async {
    try {
      await SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      );
    } catch (_) {
      // Best-effort by design: the live region already carries the message.
    }
  }

  /// Validates the fields the copy deck has messages for, setting each
  /// field's error text. Returns the first error — announced by the
  /// caller — or null when the input is clean.
  String? _validate() {
    final password = _password.text;
    final String? passwordError =
        isValidPassword(password) ? null : Copy.passwordRule;
    // A confirm mismatch reuses the password-rule copy (pinned) and is
    // shown on the confirm field, which is where the fix belongs; if the
    // rule itself fails, that error is reported on the password field.
    final String? confirmError;
    if (passwordError != null || _confirm.text == password) {
      confirmError = null;
    } else {
      confirmError = Copy.passwordRule;
    }
    final contactError = isValidContactNumber(_contact.text)
        ? null
        : Copy.contactInvalid;
    setState(() {
      _passwordError = passwordError;
      _confirmError = confirmError;
      _contactError = contactError;
    });
    return passwordError ?? confirmError ?? contactError;
  }

  Future<void> _submit() async {
    if (_auth.busy) {
      return;
    }
    final validationError = _validate();
    if (validationError != null) {
      await _announce(validationError);
      return;
    }
    _wakingTimer?.cancel();
    _wakingTimer = Timer(_wakingDelay, () {
      if (!mounted) {
        return;
      }
      setState(() => _pendingByTimer = true);
      _syncWakingBanner();
    });
    final signedIn = await _auth.signup(
      name: _name.text.trim(),
      email: _email.text.trim(),
      password: _password.text,
      contactNumber: normalizeContactNumber(_contact.text),
    );
    _wakingTimer?.cancel();
    _wakingTimer = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingByTimer = false;
      _wakingAnnounced = false;
    });
    if (signedIn) {
      Navigator.of(context).pushReplacementNamed('/permissions');
    } else {
      // `lastError` is already copy-deck text (never a raw server detail).
      final error = _auth.lastError;
      if (error != null) {
        await _announce(error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _auth.lastError;
    return Scaffold(
      appBar: AppBar(title: const Text(Copy.signUp)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VoiceField(
                label: Copy.nameLabel,
                semanticsLabel: Copy.nameLabel,
                controller: _name,
              ),
              VoiceField(
                label: Copy.emailLabel,
                semanticsLabel: Copy.loginField,
                controller: _email,
                keyboardType: TextInputType.emailAddress,
              ),
              VoiceField(
                label: Copy.passwordField,
                semanticsLabel: Copy.passwordField,
                controller: _password,
                obscure: true,
                errorText: _passwordError,
              ),
              VoiceField(
                label: Copy.passwordField,
                semanticsLabel: Copy.passwordField,
                controller: _confirm,
                obscure: true,
                errorText: _confirmError,
              ),
              VoiceField(
                label: Copy.contactNumberLabel,
                semanticsLabel: Copy.emergencyNumberField,
                controller: _contact,
                keyboardType: TextInputType.phone,
                errorText: _contactError,
              ),
              if (_showWaking) ...[
                // Live region: TalkBack reads the banner when it appears,
                // even where announcement events are deprecated (Android).
                Semantics(
                  container: true,
                  liveRegion: true,
                  child: Text(
                    Copy.serverWaking,
                    style: AppTextStyles.status.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (error != null) ...[
                // Live region: the error is announced the moment it appears,
                // not only via the best-effort announcement event.
                Semantics(
                  container: true,
                  liveRegion: true,
                  child: Text(
                    error,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.errorText,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _auth.busy ? null : _submit,
                  child: const Text(Copy.signUp),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
