import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import '../constants/copy.dart';
import '../providers/auth_provider.dart';
import '../theme/tokens.dart';
import '../widgets/voice_field.dart';

/// How long a submit may stay in flight before the waking banner appears
/// even though no retry has fired yet (a cold Render wake measured 32.5 s
/// against the 25 s client timeout).
const Duration _wakingDelay = Duration(seconds: 5);

/// Signed-out sign-in: email + password, submit, and a link to Sign up.
///
/// The "server is waking up" banner shows while `auth.retryingNetwork`
/// is true **or** a submit has been in flight for [_wakingDelay] — the
/// measured cold start on the deployed free tier (32.5 s) outlives the
/// client's 25 s timeout, so the retry signal alone would leave ~25 s of
/// silence. The timer is cancelled when the call settles and in
/// [dispose], so it can never outlive the screen or the request.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  late final AuthProvider _auth;
  Timer? _wakingTimer;
  bool _pendingByTimer = false;
  bool _wakingAnnounced = false;

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
    _email.dispose();
    _password.dispose();
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

  Future<void> _submit() async {
    if (_auth.busy) {
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
    final signedIn = await _auth.login(
      email: _email.text.trim(),
      password: _password.text,
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
      appBar: AppBar(title: const Text(Copy.logIn)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                  child: const Text(Copy.logIn),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/signup'),
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
