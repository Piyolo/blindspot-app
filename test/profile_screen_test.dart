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
import 'package:blindspot_app/screens/welcome_screen.dart';
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

/// Stand-in for the Home route beneath Profile, so stack-clearing exits
/// are observable: with a real route underneath, a plain `pushReplacement`
/// would leave Home below Welcome and `canPop()` would stay true — the
/// zombie-Home defect (F2). Absence checks must pass `skipOffstage: false`,
/// because a route beneath the top is offstage and the default finder
/// never sees it.
class HomeStub extends StatelessWidget {
  const HomeStub({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text(Copy.home)));
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

  /// Pumps the real route order around Profile — a Home route underneath,
  /// Profile pushed on top — so stack-clearing exits (logout / 401) are
  /// observable: on this stack a plain `pushReplacement` would leave Home
  /// beneath Welcome and `canPop()` would stay true (the F2 zombie-Home
  /// defect).
  Future<void> pumpProfileStacked(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ProfileProvider>.value(value: profile),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const HomeStub(),
          routes: <String, WidgetBuilder>{
            '/profile': (_) => const ProfileScreen(),
            '/welcome': (_) => const WelcomeStub(),
          },
        ),
      ),
    );
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/profile');
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
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
      'announces the saved copy exactly once, and the field follows the '
      'SERVER value (F6)',
      (tester) async {
        // The server's canonical answer is deliberately DIFFERENT from
        // the submitted number (raw and normalized), so the field can be
        // proven to follow the refreshed user, not the local fallback.
        repo.user = buildUser(contactNumber: '09199998888');
        final List<String> announcements = recordAnnouncements(tester);

        await pumpProfile(tester);
        await tester.enterText(contactField(), '0917-111-2222');
        await tapControl(
          tester,
          find.widgetWithText(ElevatedButton, Copy.save),
        );

        expect(repo.updateProfileCalls, 1);
        // Normalized to the canonical form BEFORE reaching the provider.
        expect(repo.lastContactNumber, '09171112222');
        expect(find.text(Copy.savedContact), findsOneWidget);
        // Exactly once, not merely "somewhere in the stream" (F6).
        expect(
          announcements.where((String m) => m == Copy.savedContact),
          hasLength(1),
        );
        expect(
          tester
              .getSemantics(find.text(Copy.savedContact))
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        // The displayed value comes from the provider's refreshed user —
        // the SERVER's value, which differs from what was submitted.
        final TextField contact = tester.widget<TextField>(contactField());
        expect(contact.controller!.text, '09199998888');
        expect(contact.controller!.text, isNot('09171112222'));
        expect(auth.user?.contactNumber, '09199998888');
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
        // Exactly once, not merely "somewhere in the stream" (F6).
        expect(
          announcements.where((String m) => m == Copy.passwordChanged),
          hasLength(1),
        );
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

    testWidgets(
      'answering "Yes" clears the session, lands on /welcome, and empties '
      'the whole stack',
      (tester) async {
        await pumpProfileStacked(tester);
        await tapControl(tester, find.bySemanticsLabel(Copy.logOut));
        await tester.tap(find.widgetWithText(TextButton, Copy.yes));
        await tester.pumpAndSettle();

        expect(auth.status, AuthStatus.signedOut);
        expect(auth.user, isNull);
        expect(await store.read(TokenStore.storageKey), isNull);
        expect(find.byType(WelcomeStub), findsOneWidget);
        expect(find.byType(ProfileScreen), findsNothing);
        // The WHOLE stack is cleared (F2): back from Welcome cannot reach
        // a zombie Home whose Profile tile would open a sessionless screen.
        // skipOffstage: false: a route left BENEATH the top is offstage,
        // so the default finder could never fail here — this proves the
        // stack is really emptied (F2).
        expect(find.byType(HomeStub, skipOffstage: false), findsNothing);
        expect(
          tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
          isFalse,
        );
      },
    );

    testWidgets(
      'a 401 on a contact save announces the login-error copy once and '
      'clears the whole stack into /welcome',
      (tester) async {
        repo.error = const ApiException(
          'RAW-SERVER-401-DETAIL',
          statusCode: 401,
        );
        final List<String> announcements = recordAnnouncements(tester);

        await pumpProfileStacked(tester);
        await tester.enterText(contactField(), '09181112222');
        await tapControl(
          tester,
          find.widgetWithText(ElevatedButton, Copy.save),
        );

        expect(auth.status, AuthStatus.signedOut);
        expect(find.byType(WelcomeStub), findsOneWidget);
        expect(find.byType(ProfileScreen), findsNothing);
        // The WHOLE stack is cleared (F2), so back from Welcome cannot
        // return to a signed-in-looking screen.
        // skipOffstage: false: a route left BENEATH the top is offstage,
        // so the default finder could never fail here — this proves the
        // stack is really emptied (F2).
        expect(find.byType(HomeStub, skipOffstage: false), findsNothing);
        expect(
          tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
          isFalse,
        );
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

      await pumpProfileStacked(tester);
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
      // skipOffstage: false — proves Home is removed, not merely hidden
      // beneath Welcome (F2).
      expect(find.byType(HomeStub, skipOffstage: false), findsNothing);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
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

    testWidgets('"Change password" is a navigable heading, not a control, '
        'and the action button is a separate button node', (tester) async {
      await pumpProfile(tester);

      // The section label (the first "Change password" in tree order) is
      // a heading TalkBack can navigate by — never announced as a
      // button (F4).
      final Finder headingFinder = find.text(Copy.changePasswordLabel).first;
      final SemanticsNode heading = tester.getSemantics(headingFinder);
      expect(heading.flagsCollection.isHeader, isTrue);
      expect(heading.flagsCollection.isButton, isFalse);

      // The action control keeps its own label and button semantics.
      final SemanticsNode button = tester.getSemantics(
        find.widgetWithText(ElevatedButton, Copy.changePasswordLabel),
      );
      expect(button.flagsCollection.isButton, isTrue);
      expect(button.flagsCollection.isHeader, isFalse);
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
        // F5: takeException only catches layout exceptions — inspect the
        // rendered paragraphs themselves, so a silently clipped or
        // ellipsized label would fail here too.
        final Iterable<RenderParagraph> paragraphs = tester
            .renderObjectList<RenderParagraph>(find.byType(Text));
        expect(paragraphs, isNotEmpty);
        for (final RenderParagraph paragraph in paragraphs) {
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason:
                'text scale $scale clips '
                '"${paragraph.text.toPlainText()}"',
          );
        }
      }
    });

    testWidgets('the logout confirm dialog survives 3.0x text scale on '
        '320x568 without overflow or clipping', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpProfile(tester, textScale: 3.0);
      await tester.ensureVisible(find.bySemanticsLabel(Copy.logOut));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(Copy.logOut));
      await tester.pumpAndSettle();

      expect(find.text(Copy.logoutConfirm), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'the confirm dialog overflows at 3.0x on 320x568',
      );
      final Iterable<RenderParagraph> paragraphs = tester
          .renderObjectList<RenderParagraph>(find.byType(Text));
      for (final RenderParagraph paragraph in paragraphs) {
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: 'the dialog clips "${paragraph.text.toPlainText()}" at 3.0x',
        );
      }
    });

    testWidgets("the screen's own AnnotatedRegion above the Scaffold carries "
        'the shared dark status-bar style', (tester) async {
      await pumpProfile(tester);

      // F3: the screen's OWN region — the only AnnotatedRegion that is an
      // ANCESTOR of the Scaffold. The AppBar also reports an equal-valued
      // region from inside the tree, so an all-regions check passed even
      // without the screen's own fix; this ancestor-scoped finder fails
      // when the screen's region is removed.
      final AnnotatedRegion<SystemUiOverlayStyle> region = tester.widget(
        find.ancestor(
          of: find.byType(Scaffold),
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        ),
      );
      expect(region.value, AppTheme.statusBarStyle);
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

    testWidgets('a signed-out Home cannot reach a sessionless Profile: the '
        'Profile tile redirects to /welcome and clears the stack (F2)', (
      tester,
    ) async {
      final InMemorySecureStore seeded = InMemorySecureStore();
      await seeded.write(TokenStore.storageKey, 'cached-token');
      await seeded.write(
        SessionRepository.userKey,
        jsonEncode(buildUser().toJson()),
      );

      await pumpApp(tester, store: seeded);
      expect(find.byType(HomeScreen), findsOneWidget);

      // The zombie-Home state the review found: the session dies
      // underneath a Home that is still on stage (a server-side 401 on
      // any profile call).
      final AuthProvider appAuth = tester
          .element(find.byType(HomeScreen))
          .read<AuthProvider>();
      appAuth.handleUnauthorized(401);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget); // still on stage

      await tester.tap(find.bySemanticsLabel(Copy.profileTitle));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsNothing);
      // skipOffstage: false: the old stack's Home must be REMOVED, not
      // just hidden offstage beneath Welcome (F2).
      expect(
        find.byType(HomeScreen, skipOffstage: false),
        findsNothing,
      ); // stack cleared
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
    });
  });
}
