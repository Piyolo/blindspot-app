import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/main.dart';
import 'package:blindspot_app/models/user.dart';
import 'package:blindspot_app/providers/auth_provider.dart';
import 'package:blindspot_app/providers/profile_provider.dart';
import 'package:blindspot_app/repositories/auth_repository.dart';
import 'package:blindspot_app/repositories/session_repository.dart';
import 'package:blindspot_app/screens/home_screen.dart';
import 'package:blindspot_app/screens/login_screen.dart';
import 'package:blindspot_app/screens/signup_screen.dart';
import 'package:blindspot_app/screens/splash_screen.dart';
import 'package:blindspot_app/screens/welcome_screen.dart';
import 'package:blindspot_app/services/api_client.dart';
import 'package:blindspot_app/services/secure_store.dart';
import 'package:blindspot_app/services/token_store.dart';
import 'package:blindspot_app/theme/app_theme.dart';

User cachedUser({String name = 'Ana Cruz'}) => User(
      id: 7,
      name: name,
      email: 'ana@example.com',
      contactNumber: '09171234567',
      createdAt: DateTime.utc(2026, 10, 18, 9, 30),
    );

/// Seeds [store] the way a previous successful login would have left it.
Future<void> seedSession(SecureStore store, {String name = 'Ana Cruz'}) async {
  await store.write(TokenStore.storageKey, 'cached-token');
  await store.write(
    SessionRepository.userKey,
    jsonEncode(cachedUser(name: name).toJson()),
  );
}

/// Pumps the real app graph with a fake repository and an in-memory store:
/// no real network and no real keychain ever run in a widget test.
Future<void> pumpApp(WidgetTester tester, {SecureStore? store}) =>
    tester.pumpWidget(BlindSpotApp(
      client: ApiClient(baseUrl: 'https://example.test'),
      authRepository: MockAuthRepository(),
      secureStore: store ?? InMemorySecureStore(),
    ));

/// [SecureStore] whose reads never complete — a hung platform keychain
/// read, the worst case for a blind user stuck on a splash screen.
class HungSecureStore implements SecureStore {
  @override
  Future<String?> read(String key) => Completer<String?>().future;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

/// [SecureStore] where only the token read is gated by the test, so the
/// session restore can settle *after* the splash's deadline.
class GatedSecureStore implements SecureStore {
  GatedSecureStore({required String userJson}) : _userJson = userJson;

  final Completer<String?> _tokenGate = Completer<String?>();
  final String _userJson;

  /// Releases the hung token read with a fully valid cached session.
  void releaseToken(String token) => _tokenGate.complete(token);

  @override
  Future<String?> read(String key) => key == TokenStore.storageKey
      ? _tokenGate.future
      : Future<String?>.value(_userJson);

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

/// An [ApiClient] over a [MockClient] that fails the first request with a
/// network-level error (retried once by the repositories) and succeeds
/// afterwards. [calls] counts HTTP attempts; [bodies] the JSON responses.
({ApiClient client, int Function() attempts}) retryOnceClient({
  required Map<String, dynamic> successBody,
}) {
  var attempts = 0;
  final ApiClient client = ApiClient(
    client: MockClient((http.Request request) async {
      attempts += 1;
      if (attempts == 1) {
        throw const SocketException('connection reset');
      }
      return http.Response(jsonEncode(successBody), 200);
    }),
    baseUrl: 'https://example.test',
  );
  return (client: client, attempts: () => attempts);
}

void main() {
  testWidgets('cold start with no cached session lands on Welcome',
      (tester) async {
    await pumpApp(tester);

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text(Copy.boot), findsOneWidget);

    // The local restore is already done, but the splash still holds for
    // its 800 ms minimum before replacing itself.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('a cached session relaunches straight to Home with the '
      "user's name", (tester) async {
    final InMemorySecureStore store = InMemorySecureStore();
    await seedSession(store);

    await pumpApp(tester, store: store);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(Copy.signedInAs('Ana Cruz')), findsOneWidget);
    // Restore is local-only (airplane-mode relaunch): the mock repository
    // is never touched, and no session means no Home.
  });

  testWidgets('the splash holds the screen for its full 800 ms minimum '
      'even when the store resolves instantly', (tester) async {
    await pumpApp(tester);
    // Flush the already-settled restore WITHOUT advancing time, so the
    // only thing still holding the splash is the minimum itself.
    await tester.pump();

    // 100 ms at a time: the pushed replacement route only materializes on
    // a LATER frame, so a single big pump cannot see a violated minimum.
    // A frame inside the window must always show the splash — never a
    // Welcome/Home that a shortened minimum already pushed.
    for (int elapsed = 100; elapsed < 800; elapsed += 100) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byType(SplashScreen),
        findsOneWidget,
        reason: 'splash must survive to $elapsed ms',
      );
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);
    }

    // Crossing the minimum: now — and only now — it routes.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('the splash timers are cancelled when the splash is disposed',
      (tester) async {
    await pumpApp(tester);
    await tester.pump(const Duration(milliseconds: 300));

    // Unmount before the 800 ms minimum fires; a timer that survived
    // dispose fails the binding's end-of-test pending-timer check.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(tester.takeException(), isNull);
  });

  testWidgets('a hung store read still routes off the splash within the '
      'bounded maximum', (tester) async {
    await pumpApp(tester, store: HungSecureStore());

    // Well before the bound: still on the splash.
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(SplashScreen), findsOneWidget);

    // At the bound: the safe default, restore or no restore.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('a store read that settles after the deadline cannot cause a '
      'second navigation or an exception', (tester) async {
    final GatedSecureStore store = GatedSecureStore(
      userJson: jsonEncode(cachedUser().toJson()),
    );
    await pumpApp(tester, store: store);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);

    // The "hung" read finally resolves with a full valid session — the
    // splash has already routed; this must not re-route anything.
    store.releaseToken('late-token');
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every route in the table resolves to a screen', (tester) async {
    await pumpApp(tester);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);

    final NavigatorState navigator =
        tester.state<NavigatorState>(find.byType(Navigator));

    Future<void> pushRoute(String route) async {
      navigator.pushNamed(route);
      await tester.pumpAndSettle();
      // An unregistered route throws 'Could not find a generator', so
      // surviving the push is the registration proof.
      expect(tester.takeException(), isNull, reason: 'pushing $route');
    }

    await pushRoute('/welcome');
    // Covered routes are skipped by default finders, so only the freshly
    // pushed Welcome is on stage.
    expect(find.byType(WelcomeScreen), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();

    await pushRoute('/login');
    expect(find.byType(LoginScreen), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();

    await pushRoute('/signup');
    expect(find.byType(SignupScreen), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();

    await pushRoute('/permissions');
    expect(find.widgetWithText(AppBar, Copy.permissionsTitle), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();

    await pushRoute('/profile');
    // The placeholder's AppBar title distinguishes it from Home's tile.
    expect(find.widgetWithText(AppBar, Copy.profileTitle), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();

    await pushRoute('/home');
    expect(find.byType(HomeScreen), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();
  });

  testWidgets("Home's Profile tile navigates to the /profile route",
      (tester) async {
    final InMemorySecureStore store = InMemorySecureStore();
    await seedSession(store);

    await pumpApp(tester, store: store);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(Copy.profileTitle));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, Copy.profileTitle), findsOneWidget);
  });

  testWidgets('the auth retry hook is live: retryingNetwork surfaces during '
      'the retry and clears after the call settles', (tester) async {
    final ({ApiClient client, int Function() attempts}) api =
        retryOnceClient(
      successBody: <String, dynamic>{
        'access_token': 'tok-live',
        'user': cachedUser().toJson(),
      },
    );
    await tester.pumpWidget(buildAppProviders(
      client: api.client,
      secureStore: InMemorySecureStore(),
      child: const SizedBox(),
    ));
    final AuthProvider auth =
        tester.element(find.byType(SizedBox)).read<AuthProvider>();

    final List<bool> observed = <bool>[];
    auth.addListener(() => observed.add(auth.retryingNetwork));

    final bool ok =
        await auth.login(email: 'ana@example.com', password: 'password123');

    expect(ok, isTrue);
    expect(api.attempts(), 2); // one network error, then the single retry
    // The hook is wired, not dead: the retry was surfaced to listeners...
    expect(observed, contains(true));
    // ...and the state settled back once the call finished.
    expect(auth.retryingNetwork, isFalse);
  });

  testWidgets('a profile retry never surfaces as auth retryingNetwork',
      (tester) async {
    final ({ApiClient client, int Function() attempts}) api =
        retryOnceClient(
      successBody: <String, dynamic>{'user': cachedUser().toJson()},
    );
    final InMemorySecureStore store = InMemorySecureStore();
    await seedSession(store);

    await tester.pumpWidget(buildAppProviders(
      client: api.client,
      secureStore: store,
      child: const SizedBox(),
    ));
    final Element context = tester.element(find.byType(SizedBox));
    final AuthProvider auth = context.read<AuthProvider>();
    final ProfileProvider profile = context.read<ProfileProvider>();

    await auth.restoreSession();
    final List<bool> observed = <bool>[];
    auth.addListener(() => observed.add(auth.retryingNetwork));

    final bool ok = await profile.updateContact('09181112222');

    expect(ok, isTrue);
    expect(api.attempts(), 2); // the profile repository retried once
    // Profile retries must never masquerade as auth retrying state.
    expect(observed, isNot(contains(true)));
    expect(auth.retryingNetwork, isFalse);
  });

  testWidgets('the splash carries the status-bar style in the layer tree, '
      'where the platform actually reads it', (tester) async {
    await pumpApp(tester);

    // The same mechanism AppBar uses: an AnnotatedRegion wins over the
    // imperative SystemUiOverlayStyle.light that MaterialApp's theme
    // builder re-sends during build (its statusBarColor is null).
    final AnnotatedRegion<SystemUiOverlayStyle> region = tester.widget(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );
    expect(region.value, AppTheme.statusBarStyle);
  });

  testWidgets('AppBar screens report the full status-bar style through the '
      'theme', (tester) async {
    await pumpApp(tester);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/login');
    await tester.pumpAndSettle();

    // The AppBar (Login provides no style of its own) resolves the theme's
    // appBarTheme style inside its build and reports it to the platform
    // through its own AnnotatedRegion — the mechanism that actually wins
    // over MaterialApp's imperative, colourless default. The widget's own
    // `systemOverlayStyle` property stays null by design.
    final AnnotatedRegion<SystemUiOverlayStyle> region = tester.widget(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );
    expect(region.value, AppTheme.statusBarStyle);
  });

  testWidgets('splash and Home survive 1.0x-3.0x text scale on a 320x568 '
      'screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final InMemorySecureStore store = InMemorySecureStore();
    await seedSession(store);

    for (final double scale in const <double>[1.0, 1.5, 2.0, 3.0]) {
      // Reset the element tree between scales so each iteration starts a
      // fresh app (providers and navigator state included).
      await tester.pumpWidget(const SizedBox());

      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData.fromView(tester.view)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: BlindSpotApp(
          client: ApiClient(baseUrl: 'https://example.test'),
          authRepository: MockAuthRepository(),
          secureStore: store,
        ),
      ));
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'splash at ${scale}x');

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'home at ${scale}x');
    }
  });
}
