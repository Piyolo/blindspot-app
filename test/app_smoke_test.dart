import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/main.dart';
import 'package:blindspot_app/models/user.dart';
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

  testWidgets('the splash honours the 800 ms minimum before navigating',
      (tester) async {
    await pumpApp(tester);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('the splash timer is cancelled when the splash is disposed',
      (tester) async {
    await pumpApp(tester);
    await tester.pump(const Duration(milliseconds: 300));

    // Unmount before the 800 ms timer fires; a timer that survived dispose
    // fails the binding's end-of-test pending-timer check.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

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
