import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'constants/copy.dart';
import 'providers/auth_provider.dart';
import 'providers/profile_provider.dart';
import 'repositories/auth_repository.dart';
import 'repositories/profile_repository.dart';
import 'repositories/session_repository.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/permissions_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/api_client.dart';
import 'services/permissions_service.dart';
import 'services/secure_store.dart';
import 'theme/app_theme.dart';

void main() {
  // The status bar is themed where it actually reaches the platform —
  // see [AppTheme.statusBarStyle]: through the theme's appBarTheme (every
  // AppBar re-announces it in its own AnnotatedRegion) and through each
  // AppBar-less screen's own AnnotatedRegion. An imperative call here
  // would NOT survive: MaterialApp's theme builder re-sends
  // SystemUiOverlayStyle.light (no colour) during build, overriding
  // anything set before runApp.
  runApp(const BlindSpotApp());
}

/// Wraps [child] in the provider graph the app installs above the
/// navigator: ONE shared [ApiClient] (the auth token installed by
/// [AuthProvider] must be sent along with profile calls too) and one
/// [SecureStore].
///
/// [client], [authRepository], [profileRepository] and [secureStore] are
/// test seams: production leaves them null and gets the live API client
/// plus the platform secure store. Extracted verbatim from
/// [BlindSpotApp.build] so tests verify the retry wiring against the
/// exact graph the app runs.
MultiProvider buildAppProviders({
  required Widget child,
  ApiClient? client,
  AuthRepository? authRepository,
  ProfileRepository? profileRepository,
  SecureStore? secureStore,
}) {
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
    child: child,
  );
}

/// Root widget of the BlindSpot app: wires the providers above the
/// navigator and owns the route table.
class BlindSpotApp extends StatelessWidget {
  const BlindSpotApp({
    super.key,
    this.client,
    this.authRepository,
    this.profileRepository,
    this.secureStore,
    this.permissionsService,
  });

  final ApiClient? client;
  final AuthRepository? authRepository;
  final ProfileRepository? profileRepository;
  final SecureStore? secureStore;

  /// Test seam: production leaves this null and the Permissions screen
  /// runs the live [PermissionHandlerService].
  final PermissionsService? permissionsService;

  @override
  Widget build(BuildContext context) {
    return buildAppProviders(
      client: client,
      authRepository: authRepository,
      profileRepository: profileRepository,
      secureStore: secureStore,
      child: MaterialApp(
        title: 'BlindSpot',
        theme: AppTheme.dark(),
        initialRoute: '/',
        routes: <String, WidgetBuilder>{
          '/': (_) => const SplashScreen(),
          '/welcome': (_) => const WelcomeScreen(),
          '/login': (_) => const LoginScreen(),
          '/signup': (_) => const SignupScreen(),
          '/permissions': (_) => PermissionsScreen(service: permissionsService),
          // Private placeholder: replaced by the real screen in Task 12.
          '/profile': (_) => const _ProfilePlaceholder(),
          '/home': (_) => const HomeScreen(),
        },
      ),
    );
  }
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
