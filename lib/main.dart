import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'constants/copy.dart';
import 'providers/auth_provider.dart';
import 'providers/profile_provider.dart';
import 'repositories/auth_repository.dart';
import 'repositories/profile_repository.dart';
import 'repositories/session_repository.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/api_client.dart';
import 'services/secure_store.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // AppBar-less screens (Splash, Welcome) have no theme hook for the
  // status bar, so the dark-surface/light-icons default is set once
  // globally; AppBar screens re-apply the same style via [AppTheme].
  SystemChrome.setSystemUIOverlayStyle(AppTheme.statusBarStyle);
  runApp(const BlindSpotApp());
}

/// Root widget of the BlindSpot app: wires the providers above the
/// navigator and owns the route table.
///
/// The repository/store parameters are test seams — widget tests inject
/// fakes so no real network or keychain ever runs. Production leaves them
/// null and gets the live API client plus the platform secure store.
class BlindSpotApp extends StatelessWidget {
  const BlindSpotApp({
    super.key,
    this.client,
    this.authRepository,
    this.profileRepository,
    this.secureStore,
  });

  final ApiClient? client;
  final AuthRepository? authRepository;
  final ProfileRepository? profileRepository;
  final SecureStore? secureStore;

  @override
  Widget build(BuildContext context) {
    // ONE client for both providers: the auth token installed on it by
    // AuthProvider must be sent along with profile calls too.
    final ApiClient api = client ?? ApiClient();
    final SecureStore store = secureStore ?? FlutterSecureStore();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) {
            // The repository's retry hook is fixed at construction, before
            // this provider exists; the closure only ever runs during a
            // request — i.e. after `auth` is assigned (see AuthProvider).
            late final AuthProvider auth;
            auth = AuthProvider(
              auth: authRepository ??
                  ApiAuthRepository(api, onRetry: () => auth.notifyRetrying()),
              session: SessionRepository(store),
              client: api,
            );
            return auth;
          },
        ),
        // Created after AuthProvider so `context.read<AuthProvider>()`
        // resolves (provider order in the list is the scoping order).
        // Deliberately NO `onRetry` on the profile repository: the profile
        // screens have no waking banner in Phase 1, and AuthProvider's
        // notifyRetrying() guards on busy — an auth-unrelated retry call
        // could only ever be noise.
        ChangeNotifierProvider<ProfileProvider>(
          create: (context) => ProfileProvider(
            repository: profileRepository ?? ApiProfileRepository(api),
            auth: context.read<AuthProvider>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'BlindSpot',
        theme: AppTheme.dark(),
        initialRoute: '/',
        routes: <String, WidgetBuilder>{
          '/': (_) => const SplashScreen(),
          '/welcome': (_) => const WelcomeScreen(),
          '/login': (_) => const LoginScreen(),
          '/signup': (_) => const SignupScreen(),
          // Private placeholder: replaced by the real screen in Task 11.
          '/permissions': (_) => const _PermissionsPlaceholder(),
          // Private placeholder: replaced by the real screen in Task 12.
          '/profile': (_) => const _ProfilePlaceholder(),
          '/home': (_) => const HomeScreen(),
        },
      ),
    );
  }
}

/// Stand-in for the Permissions screen (Task 11) so the auth flow's
/// `pushReplacementNamed('/permissions')` never hits a missing route.
class _PermissionsPlaceholder extends StatelessWidget {
  const _PermissionsPlaceholder();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text(Copy.permissionsTitle)),
      );
}

/// Stand-in for the Profile screen (Task 12) so Home's Profile tile never
/// hits a missing route.
class _ProfilePlaceholder extends StatelessWidget {
  const _ProfilePlaceholder();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text(Copy.profileTitle)),
      );
}
