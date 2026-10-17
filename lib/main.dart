import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const BlindSpotApp());
}

/// Root widget of the BlindSpot app.
class BlindSpotApp extends StatelessWidget {
  const BlindSpotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlindSpot',
      theme: AppTheme.dark(),
      home: const SplashScreen(),
    );
  }
}
