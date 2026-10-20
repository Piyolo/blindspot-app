import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:provider/provider.dart';

import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/main.dart';
import 'package:blindspot_app/models/api_exception.dart';
import 'package:blindspot_app/models/user.dart';
import 'package:blindspot_app/providers/auth_provider.dart';
import 'package:blindspot_app/providers/profile_provider.dart';
import 'package:blindspot_app/repositories/auth_repository.dart';
import 'package:blindspot_app/repositories/profile_repository.dart';
import 'package:blindspot_app/repositories/session_repository.dart';
import 'package:blindspot_app/screens/home_screen.dart';
import 'package:blindspot_app/screens/profile_screen.dart';
import 'package:blindspot_app/services/api_client.dart';
import 'package:blindspot_app/services/secure_store.dart';
import 'package:blindspot_app/services/token_store.dart';
import 'package:blindspot_app/theme/app_theme.dart';
import 'package:blindspot_app/widgets/big_action_tile.dart';

/// Stand-in for the Welcome route: the 401/logout tests assert the route
/// target, not the Welcome screen itself.
class WelcomeStub extends StatelessWidget {
  const WelcomeStub({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text(Copy.welcome)));
}

/// Records every announcement message sent over the accessibility channel
/// (`SemanticsService.sendAnnouncement`), so tests can assert the announced
/// copy. Mirrors the helpers in `screens_auth_test.dart` /
/// `permissions_screen_test.dart`; duplicated rather than imported so each
/// test file stays a self-contained suite.
List<String> recordAnnouncements(WidgetTester tester) {
  final List<String> messages = <String>[];
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
    () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      SystemChannels.accessibility.name,
      null,
    ),
  );
  return messages;
}

void main() {
  User buildUser({
    String name = 'Ana Cruz',
    String contactNumber = '09171234567',
  }) => User(
    id: 7,
    name: name,
    email: 'ana@example.com',
    contactNumber: contactNumber,
    createdAt: DateTime.utc(2026, 10, 18, 9, 30),
  );

  late MockAuthRepository authRepo;
  late InMemorySecureStore store;
  late AuthProvider auth;
  late MockProfileRepository repo;
  late ProfileProvider profile;

  /// The four editable fields, in tree order: contact, current, new,
  /// confirm. Email is deliberately NOT editable (read-only readout).
  Finder contactField() => find.byType(TextField).at(0);
  Finder currentPasswordField() => find.byType(TextField).at(1);
  Finder newPasswordField() => find.byType(TextField).at(2);
  Finder confirmPasswordField() => find.byType(TextField).at(3);

  /// Scrolls the control into view before tapping: the change-password
  /// button and the Log out tile sit below the fold on a small screen.
  Future<void> tapControl(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> pumpProfile(WidgetTester tester, {double? textScale}) async {
    final Widget app = MaterialApp(
      theme: AppTheme.dark(),
      home: const ProfileScreen(),
      routes: <String, WidgetBuilder>{'/welcome': (_) => const WelcomeStub()},
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ProfileProvider>.value(value: profile),
        ],
        // An override below the View's own MediaQuery wins for every
        // descendant, so text-scale tests are deterministic without
        // relying on platform-dispatcher round trips.
        child: textScale == null
            ? app
            : MediaQuery(
                data: MediaQueryData.fromView(
                  tester.view,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: app,
              ),
      ),
    );
  }

  setUp(() async {
    store = InMemorySecureStore();
    final SessionRepository session = SessionRepository(store);
    // Land in the signed-in state a profile visit starts from.
    await session.save(token: 'tok-123', user: buildUser());
    authRepo = MockAuthRepository();
    auth = AuthProvider(
      auth: authRepo,
      session: session,
      client: ApiClient(baseUrl: 'https://example.test'),
    );
    await auth.restoreSession();
    repo = MockProfileRepository(user: buildUser());
    profile = ProfileProvider(repository: repo, auth: auth);
  });

  group('ProfileScreen', () {
    testWidgets(
      'readout shows the name and email; the contact number is the one '
      'editable field',
      (tester) async {
        await pumpProfile(tester);

        expect(find.widgetWithText(AppBar, Copy.profileTitle), findsOneWidget);
        expect(find.text(Copy.nameLabel), findsOneWidget);
        expect(find.text('Ana Cruz'), findsOneWidget);
        expect(find.text(Copy.emailLabel), findsOneWidget);
        expect(find.text('ana@example.com'), findsOneWidget);
        // Exactly four editable fields (contact + three password fields):
        // the email is read-only, so no text field exists for it.
        expect(find.byType(TextField), findsNWidgets(4));
        final TextField contact = tester.widget<TextField>(contactField());
        expect(contact.controller!.text, '09171234567');
      },
    );

    testWidgets('a stale auth error from a previous screen is cleared on '
        'arrival and never rendered', (tester) async {
      authRepo.error = const ApiException('bad credentials', statusCode: 401);
      final bool ok = await auth.login(
        email: 'ana@example.com',
        password: 'password123',
      );
      expect(ok, isFalse);
      expect(auth.lastError, Copy.loginError); // seeded, before the screen

      await pumpProfile(tester);
      // Flush the clearError notification, which rides a microtask.
      await tester.pump();

      expect(auth.lastError, isNull);
      expect(find.text(Copy.loginError), findsNothing);
    });

    testWidgets(
      'saving a normalized contact calls the provider once, shows and '
      'announces the saved copy, and the field follows the refreshed '
      'user',
      (tester) async {
        repo.user = buildUser(contactNumber: '09181112222');
        final List<String> announcements = recordAnnouncements(tester);

        await pumpProfile(tester);
        await tester.enterText(contactField(), '0918-111-2222');
        await tapControl(
          tester,
          find.widgetWithText(ElevatedButton, Copy.save),
        );

        expect(repo.updateProfileCalls, 1);
        // Normalized to the canonical form BEFORE reaching the provider.
        expect(repo.lastContactNumber, '09181112222');
        expect(find.text(Copy.savedContact), findsOneWidget);
        expect(announcements, contains(Copy.savedContact));
        expect(
          tester
              .getSemantics(find.text(Copy.savedContact))
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        // The displayed value comes from the provider's refreshed user.
        final TextField contact = tester.widget<TextField>(contactField());
        expect(contact.controller!.text, '09181112222');
        expect(auth.user?.contactNumber, '09181112222');
      },
    );

    testWidgets(
      'an invalid contact shows the contact copy (live + announced) and '
      'makes zero provider calls',
      (tester) async {
        final List<String> announcements = recordAnnouncements(tester);

        await pumpProfile(tester);
        await tester.enterText(contactField(), '12');
        await tapControl(
          tester,
          find.widgetWithText(ElevatedButton, Copy.save),
        );

        expect(find.text(Copy.contactInvalid), findsOneWidget);
        expect(announcements, contains(Copy.contactInvalid));
        expect(
          tester
              .getSemantics(find.text(Copy.contactInvalid))
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        expect(repo.updateProfileCalls, 0);
        // The user's in-progress edit stays for correction; the cached user
        // is untouched.
        final TextField contact = tester.widget<TextField>(contactField());
        expect(contact.controller!.text, '12');
        expect(auth.user?.contactNumber, '09171234567');
      },
    );

    testWidgets(
      'an offline save shows the need-internet copy and the displayed '
      'value stays the cached one',
      (tester) async {
        repo.error = const ApiException('Network error'); // statusCode null
        final List<String> announcements = recordAnnouncements(tester);

        await pumpProfile(tester);
        await tester.enterText(contactField(), '09181112222');
        await tapControl(
          tester,
          find.widgetWithText(ElevatedButton, Copy.save),
        );

        expect(repo.updateProfileCalls, 1); // the call was attempted
        expect(find.text(Copy.needInternet), findsOneWidget);
        expect(announcements, contains(Copy.needInternet));
        expect(
          tester
              .getSemantics(find.text(Copy.needInternet))
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        // The edit did not take: the field shows the cached value again.
        final TextField contact = tester.widget<TextField>(contactField());
        expect(contact.controller!.text, '09171234567');
        expect(auth.user?.contactNumber, '09171234567');
        expect(find.text(Copy.savedContact), findsNothing);
      },
    );

    testWidgets('a weak new password shows the password-rule copy and never '
        'calls the provider', (tester) async {
      final List<String> announcements = recordAnnouncements(tester);

      await pumpProfile(tester);
      await tester.enterText(currentPasswordField(), 'oldpassword1');
      await tester.enterText(newPasswordField(), 'short');
      await tester.enterText(confirmPasswordField(), 'short');
      await tapControl(
        tester,
        find.widgetWithText(ElevatedButton, Copy.changePasswordLabel),
      );

      expect(find.text(Copy.passwordRule), findsOneWidget);
      expect(announcements, contains(Copy.passwordRule));
      expect(repo.changePasswordCalls, 0);
      expect(find.text(Copy.passwordMismatch), findsNothing);
    });

    testWidgets('a confirm mismatch shows the mismatch copy — not the '
        'password rule — and never calls the provider', (tester) async {
      await pumpProfile(tester);
      await tester.enterText(currentPasswordField(), 'oldpassword1');
      await tester.enterText(newPasswordField(), 'password123');
      await tester.enterText(confirmPasswordField(), 'password124');
      await tapControl(
        tester,
        find.widgetWithText(ElevatedButton, Copy.changePasswordLabel),
      );

      expect(find.text(Copy.passwordMismatch), findsOneWidget);
      expect(find.text(Copy.passwordRule), findsNothing);
      expect(repo.changePasswordCalls, 0);
    });

    testWidgets('an empty current password shows the required copy and never '
        'calls the provider', (tester) async {
      await pumpProfile(tester);
      await tester.enterText(currentPasswordField(), '');
      await tester.enterText(newPasswordField(), 'password123');
      await tester.enterText(confirmPasswordField(), 'password123');
      await tapControl(
        tester,
        find.widgetWithText(ElevatedButton, Copy.changePasswordLabel),
      );

      expect(find.text(Copy.passwordRequired), findsOneWidget);
      expect(repo.changePasswordCalls, 0);
      expect(find.byType(WelcomeStub), findsNothing);
    });

    testWidgets(
      'a wrong current password shows the dedicated copy and keeps the '
      'user signed in',
      (tester) async {
        // The server's dedicated 401 detail for a wrong current password —
        // a rejected edit, not a dead session.
        repo.error = const ApiException(
          Copy.wrongCurrentPassword,
          statusCode: 401,
        );
        final List<String> announcements = recordAnnouncements(tester);

        await pumpProfile(tester);
        await tester.enterText(currentPasswordField(), 'oldpassword1');
        await tester.enterText(newPasswordField(), 'password2');
        await tester.enterText(confirmPasswordField(), 'password2');
        await tapControl(
          tester,
          find.widgetWithText(ElevatedButton, Copy.changePasswordLabel),
        );

        expect(find.text(Copy.wrongCurrentPassword), findsOneWidget);
        expect(announcements, contains(Copy.wrongCurrentPassword));
        expect(auth.status, AuthStatus.signedIn);
        expect(find.byType(ProfileScreen), findsOneWidget);
        expect(find.byType(WelcomeStub), findsNothing);
        // The fields keep their values so only the current password needs
        // fixing.
        final TextField current = tester.widget<TextField>(
          currentPasswordField(),
        );
        expect(current.controller!.text, 'oldpassword1');
      },
    );

    testWidgets(
      'a successful password change shows and announces the confirmation '
      'and clears the three fields',
      (tester) async {
        final List<String> announcements = recordAnnouncements(tester);

        await pumpProfile(tester);
        await tester.enterText(currentPasswordField(), 'oldpassword1');
        await tester.enterText(newPasswordField(), 'password2');
        await tester.enterText(confirmPasswordField(), 'password2');
        await tapControl(
          tester,
          find.widgetWithText(ElevatedButton, Copy.changePasswordLabel),
        );

        expect(repo.changePasswordCalls, 1);
        expect(find.text(Copy.passwordChanged), findsOneWidget);
        expect(announcements, contains(Copy.passwordChanged));
        expect(
          tester
              .getSemantics(find.text(Copy.passwordChanged))
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        for (final Finder field in <Finder>[
          currentPasswordField(),
          newPasswordField(),
          confirmPasswordField(),
        ]) {
          final TextField typed = tester.widget<TextField>(field);
          expect(typed.controller!.text, isEmpty);
        }
        expect(auth.status, AuthStatus.signedIn);
      },
    );

    testWidgets('Log out asks for confirmation with the copy-deck text and '
        'Yes/No buttons', (tester) async {
      await pumpProfile(tester);
      await tapControl(tester, find.bySemanticsLabel(Copy.logOut));

      expect(find.text(Copy.logoutConfirm), findsOneWidget);
      for (final String label in <String>[Copy.yes, Copy.no]) {
        final Finder button = find.widgetWithText(TextButton, label);
        expect(button, findsOneWidget, reason: label);
        final SemanticsNode node = tester.getSemantics(button);
        expect(node.flagsCollection.isButton, isTrue, reason: label);
        final Size size = tester.getSize(button);
        expect(size.height, greaterThanOrEqualTo(48.0), reason: label);
        expect(size.width, greaterThanOrEqualTo(48.0), reason: label);
      }
      // Still signed in: asking is not doing.
      expect(auth.status, AuthStatus.signedIn);
    });

    testWidgets('answering "No" to the logout dialog changes nothing', (
      tester,
    ) async {
      await pumpProfile(tester);
      await tapControl(tester, find.bySemanticsLabel(Copy.logOut));
      await tester.tap(find.widgetWithText(TextButton, Copy.no));
      await tester.pumpAndSettle();

      expect(find.text(Copy.logoutConfirm), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(auth.status, AuthStatus.signedIn);
      expect(await store.read(TokenStore.storageKey), 'tok-123');
    });

    testWidgets('answering "Yes" clears the session and lands on /welcome', (
      tester,
    ) async {
      await pumpProfile(tester);
      await tapControl(tester, find.bySemanticsLabel(Copy.logOut));
      await tester.tap(find.widgetWithText(TextButton, Copy.yes));
      await tester.pumpAndSettle();

      expect(auth.status, AuthStatus.signedOut);
      expect(auth.user, isNull);
      expect(await store.read(TokenStore.storageKey), isNull);
      expect(find.byType(WelcomeStub), findsOneWidget);
      expect(find.byType(ProfileScreen), findsNothing);
    });

    testWidgets(
      'a 401 on a contact save announces the login-error copy once and '
      'replaces the screen with /welcome',
      (tester) async {
        repo.error = const ApiException(
          'RAW-SERVER-401-DETAIL',
          statusCode: 401,
        );
        final List<String> announcements = recordAnnouncements(tester);

        await pumpProfile(tester);
        await tester.enterText(contactField(), '09181112222');
        await tapControl(
          tester,
          find.widgetWithText(ElevatedButton, Copy.save),
        );

        expect(auth.status, AuthStatus.signedOut);
        expect(find.byType(WelcomeStub), findsOneWidget);
        // pushReplacement: back from Welcome cannot return to a signed-in
        // screen.
        expect(find.byType(ProfileScreen), findsNothing);
        expect(
          announcements.where((String m) => m == Copy.loginError),
          hasLength(1),
        );
        // The dead-session notice is announced, not rendered: the screen is
        // gone on the next frame, and a live-region copy would make
        // TalkBack read it twice.
        expect(find.text(Copy.loginError), findsNothing);
      },
    );

    testWidgets('a 401 on a password change does the same', (tester) async {
      repo.error = const ApiException('RAW-SERVER-401-DETAIL', statusCode: 401);
      final List<String> announcements = recordAnnouncements(tester);

      await pumpProfile(tester);
      await tester.enterText(currentPasswordField(), 'oldpassword1');
      await tester.enterText(newPasswordField(), 'password2');
      await tester.enterText(confirmPasswordField(), 'password2');
      await tapControl(
        tester,
        find.widgetWithText(ElevatedButton, Copy.changePasswordLabel),
      );

      expect(auth.status, AuthStatus.signedOut);
      expect(find.byType(WelcomeStub), findsOneWidget);
      expect(find.byType(ProfileScreen), findsNothing);
      expect(
        announcements.where((String m) => m == Copy.loginError),
        hasLength(1),
      );
    });

    testWidgets('every control is a 48dp+ button and each field is exactly one '
        'labelled editable node', (tester) async {
      // The form is taller than the default surface: give it room so every
      // field is visible to the semantics traversal.
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpProfile(tester);

      for (final Finder control in <Finder>[
        find.widgetWithText(ElevatedButton, Copy.save),
        find.widgetWithText(ElevatedButton, Copy.changePasswordLabel),
        find.byType(BigActionTile),
      ]) {
        final Size size = tester.getSize(control);
        expect(size.height, greaterThanOrEqualTo(48.0));
        expect(size.width, greaterThanOrEqualTo(48.0));
      }
      final SemanticsNode logout = tester.getSemantics(
        find.bySemanticsLabel(Copy.logOut),
      );
      expect(logout.flagsCollection.isButton, isTrue);

      final List<SemanticsNode> traversal = tester.semantics
          .simulatedAccessibilityTraversal()
          .toList();
      final List<SemanticsNode> fields = traversal
          .where((SemanticsNode n) => n.flagsCollection.isTextField)
          .toList(growable: false);
      // One stop per field — a labelled wrapper node flagged textField
      // beside the real edit box would read each field twice to TalkBack.
      expect(fields, hasLength(4));
      expect(fields.where((SemanticsNode n) => n.label.isEmpty), isEmpty);
      expect(fields.map((SemanticsNode n) => n.label).toSet(), <String>{
        Copy.emergencyNumberField,
        Copy.currentPasswordLabel,
        Copy.newPasswordLabel,
        Copy.confirmPasswordField,
      });
    });

    testWidgets('the screen survives 1.0x-3.0x text scale on a 320x568 '
        'screen without overflow or clipped labels', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final double scale in const <double>[1.0, 1.5, 2.0, 3.0]) {
        await pumpProfile(tester, textScale: scale);

        expect(
          tester.takeException(),
          isNull,
          reason: 'text scale $scale overflows the 320x568 screen',
        );
      }
    });

    testWidgets('every on-stage status-bar region carries the shared dark '
        'style', (tester) async {
      await pumpProfile(tester);

      final List<AnnotatedRegion<SystemUiOverlayStyle>> regions = tester
          .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          )
          .toList(growable: false);
      expect(
        regions,
        isNotEmpty,
        reason: 'the profile screen carries no status-bar style',
      );
      for (final AnnotatedRegion<SystemUiOverlayStyle> region in regions) {
        expect(region.value, AppTheme.statusBarStyle);
      }
    });
  });

  group('routing', () {
    Future<void> pumpApp(WidgetTester tester, {SecureStore? store}) async {
      await tester.pumpWidget(
        BlindSpotApp(
          client: ApiClient(baseUrl: 'https://example.test'),
          authRepository: MockAuthRepository(),
          secureStore: store ?? InMemorySecureStore(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
    }

    testWidgets('/profile resolves to the real ProfileScreen in the app '
        'route table', (tester) async {
      await pumpApp(tester);
      expect(find.text(Copy.welcome), findsOneWidget);

      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('/profile');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'pushing /profile');
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, Copy.profileTitle), findsOneWidget);
    });

    testWidgets("Home's Profile tile lands on the real ProfileScreen — no "
        'placeholder dead end', (tester) async {
      final InMemorySecureStore seeded = InMemorySecureStore();
      await seeded.write(TokenStore.storageKey, 'cached-token');
      await seeded.write(
        SessionRepository.userKey,
        jsonEncode(buildUser().toJson()),
      );

      await pumpApp(tester, store: seeded);
      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(Copy.profileTitle));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('Ana Cruz'), findsOneWidget);
    });
  });
}
