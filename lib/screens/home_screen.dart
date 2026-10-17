import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Placeholder home screen used until detection/voice features land.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BlindSpot')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Detection and voice features arrive in the next phases.',
            style: AppTextStyles.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
