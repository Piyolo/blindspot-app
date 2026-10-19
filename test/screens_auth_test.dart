import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:provider/provider.dart';

import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/models/api_exception.dart';
import 'package:blindspot_app/models/auth_result.dart';
import 'package:blindspot_app/models/user.dart';
import 'package:blindspot_app/providers/auth_provider.dart';
import 'package:blindspot_app/repositories/auth_repository.dart';
import 'package:blindspot_app/repositories/session_repository.dart';
import 'package:blindspot_app/screens/login_screen.dart';
import 'package:blindspot_app/screens/signup_screen.dart';
import 'package:blindspot_app/screens/welcome_screen.dart';
import 'package:blindspot_app/services/api_client.dart';
import 'package:blindspot_app/services/secure_store.dart';
import 'package:blindspot_app/theme/app_theme.dart';
import 'package:blindspot_app/widgets/big_action_tile.dart';

/// [AuthRepository] whose calls only settle when the test says so, for
/// pending-submit scenarios (the 5 s waking banner, double taps, busy).
class GatedAuthRepository implements AuthRepository {
  final Completer<AuthResult> loginGate = Completer<AuthResult>();
  final Completer<AuthResult> signupGate = Completer<AuthResult>();

  int loginCalls = 0;
  int signupCalls = 0;

  String? lastEmail;
  String? lastContactNumber;

  @override
  Future<AuthResult> login({required String email, required String password}) {
    loginCalls += 1;
    lastEmail = email;
    return loginGate.future;
  }

  @override
  Future<AuthResult> signup({
    required String name,
    required String email,
    required String password,
    required String contactNumber,
  }) {
    signupCalls += 1;
    lastEmail = email;
    lastContactNumber = contactNumber;
    return signupGate.future;
  }
}

AuthResult cannedAuthResult() => AuthResult(
      accessToken: 'tok-test',
      user: User(
        id: 7,
        name: 'Ana Cruz',
        email: 'ana@example.com',
        contactNumber: '09171234567',
        createdAt: DateTime.utc(2026, 10, 18, 9, 30),
      ),
    );

/// Stand-in for the Task-10 `/permissions` route.
class PermissionsStub extends StatelessWidget {
  const PermissionsStub({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text(Copy.permissionsTitle));
}

/// Records every `SemanticsService.announce` message sent over the
/// accessibility channel, so tests can assert the announced copy.
List<String> recordAnnouncements(WidgetTester tester) {
  final messages = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMessageHandler(
    SystemChannels.accessibility.name,
    (ByteData? message) async {
      final Object? json = const StandardMessageCodec().decodeMessage(message);
      if (json is Map<Object?, Object?> && json['type'] == 'announce') {
        final Object? data = json['data'];
        if (data is Map<Object?, Object?> && data['message'] is String) {
          messages.add(data['message']! as String);
        }
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockMessageHandler(SystemChannels.accessibility.name, null),
  );
  return messages;
}

void main() {
  late MockAuthRepository repo;
  late AuthProvider auth;

  AuthProvider buildAuth({AuthRepository? repository}) => AuthProvider(
        auth: repository ?? repo,
        session: SessionRepository(InMemorySecureStore()),
        client: ApiClient(baseUrl: 'https://example.test'),
      );

  Future<void> pumpAuthScreen(
    WidgetTester tester, {
    required AuthProvider provider,
    required Widget home,
    Map<String, WidgetBuilder> routes = const <String, WidgetBuilder>{},
  }) {
    return tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: home,
          routes: <String, WidgetBuilder>{
            '/permissions': (_) => const PermissionsStub(),
            ...routes,
          },
        ),
      ),
    );
  }

  Future<void> enterLoginCredentials(
    WidgetTester tester, {
    String email = 'ana@example.com',
    String password = 'password123',
  }) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), email);
    await tester.enterText(fields.at(1), password);
  }

  Future<void> enterSignupFields(
    WidgetTester tester, {
    String name = 'Ana Cruz',
    String email = 'ana@example.com',
    String password = 'password123',
    String confirm = 'password123',
    String contact = '09171234567',
  }) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), name);
    await tester.enterText(fields.at(1), email);
    await tester.enterText(fields.at(2), password);
    await tester.enterText(fields.at(3), confirm);
    await tester.enterText(fields.at(4), contact);
  }

  /// The signup form is taller than the default test surface, so the
  /// submit button must be scrolled into view before it can be tapped.
  Future<void> tapSubmit(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  setUp(() {
    repo = MockAuthRepository();
    auth = buildAuth();
  });

  group('WelcomeScreen', () {
    testWidgets('shows Log in and Sign up tiles with semantics labels',
        (tester) async {
      await pumpAuthScreen(
        tester,
        provider: auth,
        home: const WelcomeScreen(),
      );

      expect(find.bySemanticsLabel(Copy.logIn), findsOneWidget);
      expect(find.bySemanticsLabel(Copy.signUp), findsOneWidget);
      // Trusted-person note comes from the copy deck.
      expect(find.text(Copy.welcome), findsOneWidget);
      expect(find.byType(BigActionTile), findsNWidgets(2));
    });

    testWidgets('tiles are at least 48dp in both dimensions',
        (tester) async {
      await pumpAuthScreen(
        tester,
        provider: auth,
        home: const WelcomeScreen(),
      );

      final List<Element> tiles =
          find.byType(BigActionTile).evaluate().toList();
      expect(tiles, hasLength(2));
      for (final Element tile in tiles) {
        final Size size = tester.getSize(find.byWidget(tile.widget));
        expect(size.height, greaterThanOrEqualTo(48.0));
        expect(size.width, greaterThanOrEqualTo(48.0));
      }
      // Pinned by spec §5.3: tiles are 56 dp high.
      expect(tester.getSize(find.byType(BigActionTile).first).height, 56.0);
    });

    testWidgets('Log in tile navigates to the login screen', (tester) async {
      await pumpAuthScreen(
        tester,
        provider: auth,
        home: const WelcomeScreen(),
        routes: <String, WidgetBuilder>{
          '/login': (_) => const LoginScreen(),
          '/signup': (_) => const SignupScreen(),
        },
      );

      await tester.tap(find.bySemanticsLabel(Copy.logIn));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('LoginScreen', () {
    testWidgets('submit calls login once and navigates to /permissions',
        (tester) async {
      await pumpAuthScreen(tester, provider: auth, home: const LoginScreen());

      await enterLoginCredentials(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, Copy.logIn));
      await tester.pumpAndSettle();

      expect(repo.loginCalls, 1);
      expect(repo.lastEmail, 'ana@example.com');
      expect(find.byType(PermissionsStub), findsOneWidget);
    });

    testWidgets('password field is obscured and labelled via semantics',
        (tester) async {
      await pumpAuthScreen(tester, provider: auth, home: const LoginScreen());

      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList(growable: false);
      expect(fields[0].obscureText, isFalse);
      expect(fields[1].obscureText, isTrue);

      final SemanticsNode email =
          tester.getSemantics(find.bySemanticsLabel(Copy.loginField));
      expect(email.flagsCollection.isTextField, isTrue);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(Copy.passwordField))
            .flagsCollection
            .isTextField,
        isTrue,
      );
    });

    testWidgets('401 renders and announces the login-error copy',
        (tester) async {
      repo.error = const ApiException('bad credentials', statusCode: 401);
      final List<String> announcements = recordAnnouncements(tester);

      await pumpAuthScreen(tester, provider: auth, home: const LoginScreen());
      await enterLoginCredentials(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, Copy.logIn));
      await tester.pumpAndSettle();

      expect(find.text(Copy.loginError), findsOneWidget);
      expect(announcements, contains(Copy.loginError));
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets(
        'waking banner appears after 5 s of a pending submit and clears '
        'when it settles', (tester) async {
      final GatedAuthRepository gated = GatedAuthRepository();
      auth = buildAuth(repository: gated);
      final List<String> announcements = recordAnnouncements(tester);

      await pumpAuthScreen(tester, provider: auth, home: const LoginScreen());
      await enterLoginCredentials(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, Copy.logIn));
      await tester.pump();

      expect(find.text(Copy.serverWaking), findsNothing);

      await tester.pump(const Duration(seconds: 5));

      expect(find.text(Copy.serverWaking), findsOneWidget);
      expect(announcements, contains(Copy.serverWaking));

      gated.loginGate.complete(cannedAuthResult());
      await tester.pumpAndSettle();

      expect(find.text(Copy.serverWaking), findsNothing);
      expect(find.byType(PermissionsStub), findsOneWidget);
      // A leaked 5 s timer would surface in the binding's teardown check.
    });

    testWidgets('waking banner appears while the repository retries',
        (tester) async {
      final GatedAuthRepository gated = GatedAuthRepository();
      auth = buildAuth(repository: gated);
      final List<String> announcements = recordAnnouncements(tester);

      await pumpAuthScreen(tester, provider: auth, home: const LoginScreen());
      await enterLoginCredentials(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, Copy.logIn));
      await tester.pump();

      auth.notifyRetrying();
      await tester.pump();

      expect(find.text(Copy.serverWaking), findsOneWidget);
      expect(announcements, contains(Copy.serverWaking));

      gated.loginGate.completeError(const ApiException('offline'));
      await tester.pumpAndSettle();

      expect(find.text(Copy.serverWaking), findsNothing);
      expect(find.text(Copy.offline), findsOneWidget);
    });

    testWidgets(
        'a submit that settles before 5 s shows no banner and leaves no '
        'pending timer', (tester) async {
      final GatedAuthRepository gated = GatedAuthRepository();
      auth = buildAuth(repository: gated);

      await pumpAuthScreen(tester, provider: auth, home: const LoginScreen());
      await enterLoginCredentials(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, Copy.logIn));
      await tester.pump();

      gated.loginGate.completeError(const ApiException('bad', statusCode: 401));
      await tester.pumpAndSettle();

      expect(find.text(Copy.serverWaking), findsNothing);
      expect(find.text(Copy.loginError), findsOneWidget);

      // Far past the 5 s mark: a leaked timer would fire (or fail the
      // binding's pending-timer check) here.
      await tester.pump(const Duration(seconds: 10));
      expect(find.text(Copy.serverWaking), findsNothing);
    });

    testWidgets('the waking timer is cancelled when the screen is disposed',
        (tester) async {
      final GatedAuthRepository gated = GatedAuthRepository();
      auth = buildAuth(repository: gated);

      await pumpAuthScreen(tester, provider: auth, home: const LoginScreen());
      await enterLoginCredentials(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, Copy.logIn));
      await tester.pump(const Duration(seconds: 3));

      // Unmount the screen mid-submit; the gate is never completed.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 10));

      expect(tester.takeException(), isNull);
    });

    testWidgets('two rapid taps issue exactly one login call', (tester) async {
      final GatedAuthRepository gated = GatedAuthRepository();
      auth = buildAuth(repository: gated);

      await pumpAuthScreen(tester, provider: auth, home: const LoginScreen());
      await enterLoginCredentials(tester);

      final Finder submit = find.widgetWithText(ElevatedButton, Copy.logIn);
      await tester.tap(submit);
      await tester.tap(submit);
      await tester.pump();

      expect(gated.loginCalls, 1);
      // Submit is disabled for the whole in-flight window.
      expect(tester.widget<ElevatedButton>(submit).onPressed, isNull);

      gated.loginGate.complete(cannedAuthResult());
      await tester.pumpAndSettle();

      expect(gated.loginCalls, 1);
      expect(find.byType(PermissionsStub), findsOneWidget);
    });
  });

  group('SignupScreen', () {
    testWidgets(
        'a bad password shows the password-rule copy and never calls the '
        'repository', (tester) async {
      final List<String> announcements = recordAnnouncements(tester);

      await pumpAuthScreen(tester, provider: auth, home: const SignupScreen());
      await enterSignupFields(tester, password: 'short', confirm: 'short');
      await tapSubmit(tester, find.widgetWithText(ElevatedButton, Copy.signUp));
      await tester.pump();

      expect(find.text(Copy.passwordRule), findsOneWidget);
      expect(repo.signupCalls, 0);
      expect(announcements, contains(Copy.passwordRule));
      expect(find.byType(SignupScreen), findsOneWidget);
    });

    testWidgets('a confirm mismatch reuses the password-rule copy',
        (tester) async {
      await pumpAuthScreen(tester, provider: auth, home: const SignupScreen());
      await enterSignupFields(
        tester,
        password: 'password123',
        confirm: 'password124',
      );
      await tapSubmit(tester, find.widgetWithText(ElevatedButton, Copy.signUp));
      await tester.pump();

      expect(find.text(Copy.passwordRule), findsOneWidget);
      expect(repo.signupCalls, 0);
    });

    testWidgets('an invalid contact number shows the contact copy',
        (tester) async {
      final List<String> announcements = recordAnnouncements(tester);

      await pumpAuthScreen(tester, provider: auth, home: const SignupScreen());
      await enterSignupFields(tester, contact: '12');
      await tapSubmit(tester, find.widgetWithText(ElevatedButton, Copy.signUp));
      await tester.pump();

      expect(find.text(Copy.contactInvalid), findsOneWidget);
      expect(repo.signupCalls, 0);
      expect(announcements, contains(Copy.contactInvalid));
    });

    testWidgets('normalizes the contact number before submit', (tester) async {
      await pumpAuthScreen(tester, provider: auth, home: const SignupScreen());
      await enterSignupFields(tester, contact: '0917 123-4567');
      await tapSubmit(tester, find.widgetWithText(ElevatedButton, Copy.signUp));
      await tester.pumpAndSettle();

      expect(repo.signupCalls, 1);
      expect(repo.lastContactNumber, '09171234567');
      expect(find.byType(PermissionsStub), findsOneWidget);
    });

    testWidgets('keeps a plus-six-three prefix when normalizing',
        (tester) async {
      await pumpAuthScreen(tester, provider: auth, home: const SignupScreen());
      await enterSignupFields(tester, contact: '+63 917 123 4567');
      await tapSubmit(tester, find.widgetWithText(ElevatedButton, Copy.signUp));
      await tester.pumpAndSettle();

      expect(repo.signupCalls, 1);
      expect(repo.lastContactNumber, '+639171234567');
    });

    testWidgets('409 renders and announces the email-exists copy',
        (tester) async {
      repo.error =
          const ApiException('conflict', statusCode: 409);
      final List<String> announcements = recordAnnouncements(tester);

      await pumpAuthScreen(tester, provider: auth, home: const SignupScreen());
      await enterSignupFields(tester);
      await tapSubmit(tester, find.widgetWithText(ElevatedButton, Copy.signUp));
      await tester.pumpAndSettle();

      expect(find.text(Copy.emailExists), findsOneWidget);
      expect(announcements, contains(Copy.emailExists));
      expect(find.byType(SignupScreen), findsOneWidget);
    });

    testWidgets('password and confirm fields are obscured', (tester) async {
      await pumpAuthScreen(tester, provider: auth, home: const SignupScreen());

      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList(growable: false);
      expect(fields[0].obscureText, isFalse); // name
      expect(fields[1].obscureText, isFalse); // email
      expect(fields[2].obscureText, isTrue); // password
      expect(fields[3].obscureText, isTrue); // confirm
      expect(fields[4].obscureText, isFalse); // contact
    });

    testWidgets('submit is disabled while busy; one call per double tap',
        (tester) async {
      final GatedAuthRepository gated = GatedAuthRepository();
      auth = buildAuth(repository: gated);

      await pumpAuthScreen(tester, provider: auth, home: const SignupScreen());
      await enterSignupFields(tester);

      final Finder submit = find.widgetWithText(ElevatedButton, Copy.signUp);
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      // Two taps in the same frame: the second reaches the still-enabled
      // button and must be swallowed by the busy guard.
      await tester.tap(submit);
      await tester.tap(submit);
      await tester.pump();

      expect(gated.signupCalls, 1);
      expect(tester.widget<ElevatedButton>(submit).onPressed, isNull);

      gated.signupGate.complete(cannedAuthResult());
      await tester.pumpAndSettle();

      expect(gated.signupCalls, 1);
      expect(find.byType(PermissionsStub), findsOneWidget);
    });
  });
}
