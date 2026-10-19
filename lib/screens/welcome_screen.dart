import 'package:flutter/material.dart';

import '../constants/copy.dart';
import '../theme/tokens.dart';
import '../widgets/big_action_tile.dart';

/// Signed-out entry point: two big choices (Log in / Sign up) plus the
/// trusted-person note from the copy deck.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                Copy.welcome,
                style: AppTextStyles.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              BigActionTile(
                label: Copy.logIn,
                icon: Icons.login,
                onTap: () => Navigator.of(context).pushNamed('/login'),
              ),
              const SizedBox(height: 16),
              BigActionTile(
                label: Copy.signUp,
                icon: Icons.person_add,
                onTap: () => Navigator.of(context).pushNamed('/signup'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
