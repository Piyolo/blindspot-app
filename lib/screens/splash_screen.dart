import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/copy.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Launch screen: shows the boot copy while the cached session is restored
/// from local storage — no network, so an airplane-mode relaunch still
/// reaches Home — then replaces itself with `/home` when signed in, or
/// `/welcome` otherwise.
///
/// The restore runs inside a bounded window: the screen is always shown
/// for at least 800 ms (never a flash), and it never waits longer than
/// 5 s for the store — a hung platform keychain read must not trap a
/// blind user on a dead splash with no feedback; past the deadline it
/// routes on the safe default. Both timers are cancelled in [dispose],
/// so unmounting the splash mid-wait never leaves a pending timer, and a
/// restore that settles *after* the deadline can neither navigate a
/// second time nor touch a disposed context ([_advanced] + [mounted]).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// The splash's lower bound: always visible this long, even when the
  /// store resolves instantly.
  static const Duration minimumShown = Duration(milliseconds: 800);

  /// The splash's upper bound on the local restore.
  static const Duration restoreDeadline = Duration(seconds: 5);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final Completer<void> _advance = Completer<void>();
  Timer? _minimumTimer;
  Timer? _deadlineTimer;
  bool _minimumElapsed = false;
  bool _deadlineElapsed = false;
  bool _restoreSettled = false;
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _minimumTimer = Timer(SplashScreen.minimumShown, () {
      _minimumElapsed = true;
      _maybeAdvance();
    });
    _deadlineTimer = Timer(SplashScreen.restoreDeadline, () {
      _deadlineElapsed = true;
      _maybeAdvance();
    });
    _routeWhenReady();
  }

  @override
  void dispose() {
    _minimumTimer?.cancel();
    _deadlineTimer?.cancel();
    super.dispose();
  }

  /// `restoreSession()` never throws by contract (an unreadable store
  /// signs out instead of failing the launch) and both destination
  /// routes are always registered, so this cannot fail the launch.
  Future<void> _routeWhenReady() async {
    final AuthProvider auth = context.read<AuthProvider>();
    // Not awaited: a hung store read must not hold up the deadline, which
    // routes on the safe default on its own via [_maybeAdvance].
    unawaited(auth.restoreSession().then((_) {
      _restoreSettled = true;
      _maybeAdvance();
    }));
    await _advance.future;
    if (!mounted || _advanced) {
      // Disposed mid-wait (a test unmounting the splash), or the deadline
      // already routed while the restore settled late: a late restore
      // must never navigate a second time or touch a dead context.
      return;
    }
    _advanced = true;
    Navigator.of(context).pushReplacementNamed(
      auth.status == AuthStatus.signedIn ? '/home' : '/welcome',
    );
  }

  /// Releases navigation when the minimum AND the restore have both
  /// settled — or when the deadline forces the safe default past a hung
  /// store. Single-shot: whichever path fires first wins.
  void _maybeAdvance() {
    if (_advance.isCompleted) {
      return;
    }
    if ((_restoreSettled && _minimumElapsed) || _deadlineElapsed) {
      _advance.complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The same mechanism AppBar uses to beat the imperative
    // SystemUiOverlayStyle.light (no colour) that MaterialApp's theme
    // builder re-sends during build: a layer-tree AnnotatedRegion, so the
    // dark status-bar background actually reaches the platform on this
    // AppBar-less screen.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.statusBarStyle,
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/ic_eye.png', width: 96),
              const SizedBox(height: 16),
              // Body size, not display size: at 3.0x the longer style
              // would push the brand word past a 320 dp screen instead of
              // letting the line wrap.
              const Text(
                Copy.boot,
                style: AppTextStyles.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
