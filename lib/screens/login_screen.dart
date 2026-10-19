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

/// Signed-out sign-in: email + password, submit, and a link to Sign up.
///
/// Validation runs before anything reaches the repository: an empty or
/// malformed email and an empty password have copy-deck messages, so a
/// blank submit never burns a network round trip just to surface
/// [Copy.genericError].
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
  String? _emailError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    // A failure from a previous screen (e.g. a signup 409) must never
    // render as a live-region error on a freshly opened Login.
    _auth.clearError();
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

  /// Client-side validation before anything reaches the repository, plus
  /// the announcement dedupe: [changed] is true only when some field's
  /// error text actually differs from what was already on screen, so a
  /// double-tap on the same invalid input does not make TalkBack read the
  /// same sentence twice.
  ({String? error, bool changed}) _validate() {
    final String? previousEmailError = _emailError;
    final String? previousPasswordError = _passwordError;
    final String? emailError = isValidEmail(_email.text.trim())
        ? null
        : Copy.emailInvalid;
    final String? passwordError = _password.text.isEmpty
        ? Copy.passwordRequired
        : null;
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
    });
    final bool changed = emailError != previousEmailError ||
        passwordError != previousPasswordError;
    return (error: emailError ?? passwordError, changed: changed);
  }

  Future<void> _submit() async {
    if (_auth.busy) {
      return;
    }
    // Validation errors render immediately (live region on the field) and
    // are announced only on an error transition; nothing reaches the
    // repository while the input is invalid.
    final (:error, :changed) = _validate();
    if (error != null) {
      if (changed) {
        await _announce(error);
      }
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
                errorText: _emailError,
              ),
              VoiceField(
                label: Copy.passwordField,
                semanticsLabel: Copy.passwordField,
                controller: _password,
                obscure: true,
                errorText: _passwordError,
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
              // 56/48 dp are minimum heights, not fixed sizes: at large
              // text scales the labels lay out fully and the controls
              // grow instead of clipping.
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: ElevatedButton(
                  onPressed: _auth.busy ? null : _submit,
                  child: const Text(Copy.logIn),
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
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
