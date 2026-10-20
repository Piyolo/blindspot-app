import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:provider/provider.dart';

import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/main.dart';
import 'package:blindspot_app/providers/auth_provider.dart';
import 'package:blindspot_app/repositories/auth_repository.dart';
import 'package:blindspot_app/repositories/session_repository.dart';
import 'package:blindspot_app/screens/home_screen.dart';
import 'package:blindspot_app/screens/permissions_screen.dart';
import 'package:blindspot_app/screens/splash_screen.dart';
import 'package:blindspot_app/screens/welcome_screen.dart';
import 'package:blindspot_app/services/api_client.dart';
import 'package:blindspot_app/services/permissions_service.dart';
import 'package:blindspot_app/services/secure_store.dart';
import 'package:blindspot_app/theme/app_theme.dart';
import 'package:blindspot_app/widgets/permission_card.dart';

/// Stand-in for the Home route: continue tests assert the route target,
/// not the Home screen itself (Task 10 covers that screen).
class HomeStub extends StatelessWidget {
  const HomeStub({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text(Copy.home)));
}

/// Records every announcement message sent over the accessibility channel
/// (`SemanticsService.sendAnnouncement`), so tests can assert the announced
/// copy. Mirrors the helper in `screens_auth_test.dart`; duplicated rather
/// than imported so each test file stays a self-contained suite.
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
    () => tester.binding.defaultBinaryMessenger
        .setMockMessageHandler(SystemChannels.accessibility.name, null),
  );
  return messages;
}

void main() {
  Future<void> pumpPermissions(
    WidgetTester tester, {
    required PermissionsService service,
    double? textScale,
  }) {
    final Widget app = MaterialApp(
      theme: AppTheme.dark(),
      home: PermissionsScreen(service: service),
      routes: <String, WidgetBuilder>{
        '/home': (_) => const HomeStub(),
      },
    );
    return tester.pumpWidget(
      // An override below the View's own MediaQuery wins for every
      // descendant, so text-scale tests are deterministic without
      // relying on platform-dispatcher round trips.
      textScale == null
          ? app
          : MediaQuery(
              data: MediaQueryData.fromView(tester.view)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: app,
            ),
    );
  }

  /// Asserts every on-stage `AnnotatedRegion<SystemUiOverlayStyle>` — the
  /// layer-tree carrier the platform actually reads — is the shared dark
  /// style. [screen] names the screen for the failure message.
  void expectDarkStatusBarRegions(WidgetTester tester, String screen) {
    final List<AnnotatedRegion<SystemUiOverlayStyle>> regions = tester
        .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        )
        .toList(growable: false);
    expect(regions, isNotEmpty, reason: '$screen carries no status-bar style');
    for (final AnnotatedRegion<SystemUiOverlayStyle> region in regions) {
      expect(region.value, AppTheme.statusBarStyle, reason: screen);
    }
  }

  group('PermissionsScreen', () {
    testWidgets(
        'the three cards render with the copy-deck titles, explanations '
        'and states', (tester) async {
      await pumpPermissions(tester, service: FakePermissionsService());
      await tester.pumpAndSettle();

      expect(find.byType(PermissionCard), findsNWidgets(3));
      expect(find.widgetWithText(AppBar, Copy.permissionsTitle), findsOneWidget);

      expect(find.text(Copy.microphoneLabel), findsOneWidget);
      expect(find.text(Copy.cameraLabel), findsOneWidget);
      expect(find.text(Copy.phoneLabel), findsOneWidget);
      expect(find.text(Copy.micPermission), findsOneWidget);
      expect(find.text(Copy.cameraPermission), findsOneWidget);
      expect(find.text(Copy.phonePermission), findsOneWidget);

      // Denied state is textual, never colour-only, and every card offers
      // the deck's Allow button.
      expect(find.text(Copy.permissionNotGranted), findsNWidgets(3));
      expect(find.text(Copy.permissionGranted), findsNothing);
      expect(find.widgetWithText(ElevatedButton, Copy.allow), findsNWidgets(3));
      // No all-set copy while permissions are missing.
      expect(find.text(Copy.allSet), findsNothing);
      expect(find.widgetWithText(ElevatedButton, Copy.continueLabel),
          findsOneWidget);
    });

    testWidgets('entering the screen only reads state — it never '
        'auto-requests', (tester) async {
      final FakePermissionsService fake = FakePermissionsService(
        granted: const <AppPermission, bool>{
          AppPermission.microphone: false,
          AppPermission.camera: true,
          AppPermission.phone: false,
        },
      );

      await pumpPermissions(tester, service: fake);
      await tester.pumpAndSettle();

      // One read per permission...
      expect(fake.reads, hasLength(3));
      expect(
        fake.reads.toSet(),
        <AppPermission>{
          AppPermission.microphone,
          AppPermission.camera,
          AppPermission.phone,
        },
      );
      // ...and not a single system request.
      expect(fake.requests, isEmpty);
      expect(find.text(Copy.permissionGranted), findsOneWidget);
      expect(find.text(Copy.permissionNotGranted), findsNWidgets(2));
    });

    testWidgets("tapping a card's Allow calls the service once and flips "
        "only that card's state", (tester) async {
      final FakePermissionsService fake = FakePermissionsService();

      await pumpPermissions(tester, service: fake);
      await tester.pumpAndSettle();

      // Cards are ordered mic, camera, phone; the first Allow is the mic
      // card's.
      await tester.tap(find.widgetWithText(ElevatedButton, Copy.allow).first);
      await tester.pumpAndSettle();

      expect(fake.requests, <AppPermission>[AppPermission.microphone]);
      expect(find.text(Copy.permissionGranted), findsOneWidget);
      expect(find.text(Copy.permissionNotGranted), findsNWidgets(2));
      // The granted card no longer offers Allow; the others still do.
      expect(find.widgetWithText(ElevatedButton, Copy.allow), findsNWidgets(2));
      // Still on the screen — a request never navigates away.
      expect(find.byType(PermissionsScreen), findsOneWidget);
      // The request is not re-read back from the service: one call total.
      expect(fake.reads, hasLength(3));
    });

    testWidgets("a card's state is exposed as its semantics value and the "
        'state change lands in a live region', (tester) async {
      final FakePermissionsService fake = FakePermissionsService();

      await pumpPermissions(tester, service: fake);
      await tester.pumpAndSettle();

      final SemanticsNode denied = tester
          .getSemantics(find.bySemanticsLabel(Copy.microphoneLabel));
      expect(denied.value, Copy.permissionNotGranted);
      expect(denied.flagsCollection.isLiveRegion, isTrue);

      await tester.tap(find.widgetWithText(ElevatedButton, Copy.allow).first);
      await tester.pumpAndSettle();

      final SemanticsNode granted = tester
          .getSemantics(find.bySemanticsLabel(Copy.microphoneLabel));
      expect(granted.value, Copy.permissionGranted);
      // The live region survives the flip, so TalkBack hears the change.
      expect(granted.flagsCollection.isLiveRegion, isTrue);
    });

    testWidgets('all three granted shows the all-set copy instead of the '
        'denied states', (tester) async {
      await pumpPermissions(
        tester,
        service: FakePermissionsService(
          granted: const <AppPermission, bool>{
            AppPermission.microphone: true,
            AppPermission.camera: true,
            AppPermission.phone: true,
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(Copy.allSet), findsOneWidget);
      expect(find.text(Copy.permissionGranted), findsNWidgets(3));
      expect(find.text(Copy.permissionNotGranted), findsNothing);
      // Nothing left to request.
      expect(find.widgetWithText(ElevatedButton, Copy.allow), findsNothing);
      // The all-set line is announced by the live region, not shown alone.
      expect(
        tester.getSemantics(find.text(Copy.allSet)).flagsCollection.isLiveRegion,
        isTrue,
      );
    });

    testWidgets('Continue with everything granted routes to /home with no '
        'limited-mode announcement', (tester) async {
      final List<String> announcements = recordAnnouncements(tester);

      await pumpPermissions(
        tester,
        service: FakePermissionsService(
          granted: const <AppPermission, bool>{
            AppPermission.microphone: true,
            AppPermission.camera: true,
            AppPermission.phone: true,
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, Copy.continueLabel),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, Copy.continueLabel));
      await tester.pumpAndSettle();

      expect(find.byType(HomeStub), findsOneWidget);
      expect(
        announcements.where((String m) => m == Copy.limitedMode),
        isEmpty,
      );
    });

    testWidgets('Continue with a missing permission announces limited mode '
        'exactly once and still routes to /home', (tester) async {
      final List<String> announcements = recordAnnouncements(tester);

      await pumpPermissions(
        tester,
        // Camera stays denied (its request outcome is false).
        service: FakePermissionsService(
          granted: const <AppPermission, bool>{
            AppPermission.microphone: true,
            AppPermission.phone: true,
          },
          requestOutcomes: const <AppPermission, bool>{
            AppPermission.camera: false,
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, Copy.continueLabel),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, Copy.continueLabel));
      await tester.pumpAndSettle();

      expect(find.byType(HomeStub), findsOneWidget);
      expect(
        announcements.where((String m) => m == Copy.limitedMode),
        hasLength(1),
      );
    });

    testWidgets('Allow and Continue are at least 48 dp in both dimensions',
        (tester) async {
      await pumpPermissions(tester, service: FakePermissionsService());
      await tester.pumpAndSettle();

      final List<Element> buttons =
          find.byType(ElevatedButton).evaluate().toList(growable: false);
      expect(buttons, hasLength(4)); // three Allow + one Continue
      for (final Element button in buttons) {
        final Size size = tester.getSize(find.byWidget(button.widget));
        expect(size.height, greaterThanOrEqualTo(48.0));
        expect(size.width, greaterThanOrEqualTo(48.0));
      }
    });

    testWidgets('no overflow at text scales from 1.0x to 3.0x on a small '
        '320x568 screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final double scale in const <double>[1.0, 1.5, 2.0, 3.0]) {
        await pumpPermissions(
          tester,
          service: FakePermissionsService(),
          textScale: scale,
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'text scale $scale overflows the 320x568 screen',
        );
      }
    });
  });

  group('routing and platform theming', () {
    testWidgets('the /permissions route resolves to the real screen and '
        'entering through it never auto-requests', (tester) async {
      final FakePermissionsService fake = FakePermissionsService();

      // The real route table with a fake permission service: no platform
      // channel is ever touched in a widget test.
      await tester.pumpWidget(BlindSpotApp(
        client: ApiClient(baseUrl: 'https://example.test'),
        authRepository: MockAuthRepository(),
        secureStore: InMemorySecureStore(),
        permissionsService: fake,
      ));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);

      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('/permissions');
      await tester.pumpAndSettle();

      expect(find.byType(PermissionsScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, Copy.permissionsTitle), findsOneWidget);
      // The route builds the real screen, and arriving there only reads.
      expect(fake.reads, hasLength(3));
      expect(fake.requests, isEmpty);
    });

    testWidgets('Welcome, Home, Splash and Permissions all carry the dark '
        'status-bar style', (tester) async {
      // Welcome (AppBar-less).
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: const WelcomeScreen(),
      ));
      expectDarkStatusBarRegions(tester, 'WelcomeScreen');

      // Home (AppBar-less; user null is the defensive state Home guards).
      final AuthProvider auth = AuthProvider(
        auth: MockAuthRepository(),
        session: SessionRepository(InMemorySecureStore()),
        client: ApiClient(baseUrl: 'https://example.test'),
      );
      await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const HomeScreen(),
        ),
      ));
      expectDarkStatusBarRegions(tester, 'HomeScreen');

      // Splash (AppBar-less). Disposing the tree cancels both splash
      // timers before the binding's end-of-test timer check; the dark
      // theme stays on so the next screen's theme transition cannot make
      // its AppBar compute a mid-animation style.
      await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const SplashScreen(),
        ),
      ));
      expectDarkStatusBarRegions(tester, 'SplashScreen');
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: const SizedBox(),
      ));

      // Permissions (own region plus the AppBar's, both the same style).
      await pumpPermissions(tester, service: FakePermissionsService());
      await tester.pumpAndSettle();
      expectDarkStatusBarRegions(tester, 'PermissionsScreen');
    });
  });
}
