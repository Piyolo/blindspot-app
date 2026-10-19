import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/copy.dart';
import '../providers/auth_provider.dart';
import '../theme/tokens.dart';

/// Launch screen: shows the boot copy while the cached session is restored
/// from local storage — no network, so an airplane-mode relaunch still
/// reaches Home — then replaces itself with `/home` when signed in, or
/// `/welcome` otherwise.
///
/// The restore and a fixed 800 ms minimum run concurrently: the screen
/// never hangs on a slow store and never flashes past unnoticed. The
/// timer is cancelled in [dispose], so unmounting the splash mid-wait
/// (a test, or the user leaving) never leaves a pending timer.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final Completer<void> _minimumShown = Completer<void>();
  Timer? _minimumTimer;

  @override
  void initState() {
    super.initState();
    _minimumTimer = Timer(const Duration(milliseconds: 800), () {
      _minimumShown.complete();
    });
    _routeAfterRestore();
  }

  @override
  void dispose() {
    _minimumTimer?.cancel();
    super.dispose();
  }

  /// `restoreSession()` never throws by contract (an unreadable store
  /// signs out instead of failing the launch) and both destination routes
  /// are always registered, so this cannot fail the launch.
  Future<void> _routeAfterRestore() async {
    final AuthProvider auth = context.read<AuthProvider>();
    await Future.wait<void>([auth.restoreSession(), _minimumShown.future]);
    if (!mounted) {
      // Disposed mid-wait (e.g. a test unmounting the splash): nobody is
      // waiting for the route any more.
      return;
    }
    Navigator.of(context).pushReplacementNamed(
      auth.status == AuthStatus.signedIn ? '/home' : '/welcome',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/ic_eye.png', width: 96),
            const SizedBox(height: 16),
            // Body size, not display size: at 3.0x the longer style would
            // push the brand word past a 320 dp screen instead of letting
            // the line wrap.
            const Text(
              Copy.boot,
              style: AppTextStyles.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
