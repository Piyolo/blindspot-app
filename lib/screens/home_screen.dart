import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/copy.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../theme/tokens.dart';
import '../widgets/big_action_tile.dart';

/// Minimal honest Home for Phase 1: the signed-in status strip plus the
/// one choice that works today — Profile. The other designed tiles appear
/// as their phases land, so a blind user never meets a dead control.
///
/// Like Welcome, the body scrolls: at large text scales (up to 3.0x) the
/// content is far taller than a small phone screen, and the only
/// alternative would be a hard RenderFlex overflow — a broken screen for
/// a blind user's TalkBack reading position.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // watch, not read: Task 12's Profile screen can change the name via
    // AuthProvider.replaceUser, and the strip must follow it.
    final User? user = context.watch<AuthProvider>().user;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (user != null) ...[
                // Live region: when the name changes (Task 12 edit), the
                // updated strip is announced, not just redrawn. Routing
                // guarantees a signed-in user here; the guard keeps a
                // defensive null from crashing the screen.
                Semantics(
                  container: true,
                  liveRegion: true,
                  child: Text(
                    Copy.signedInAs(user.name),
                    style: AppTextStyles.screenTitle,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              // The only working tile in Phase 1; BigActionTile carries the
              // button semantics, the label, and the 56 dp minimum height.
              BigActionTile(
                label: Copy.profileTitle,
                icon: Icons.person,
                onTap: () => Navigator.of(context).pushNamed('/profile'),
              ),
              const SizedBox(height: 24),
              // The copy deck's home line — no new keys may be added in
              // Phase 1; detection and voice make it true in Phase 2.
              const Text(
                Copy.home,
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
