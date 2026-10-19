import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:provider/provider.dart';

import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/models/user.dart';
import 'package:blindspot_app/providers/auth_provider.dart';
import 'package:blindspot_app/repositories/auth_repository.dart';
import 'package:blindspot_app/repositories/session_repository.dart';
import 'package:blindspot_app/screens/home_screen.dart';
import 'package:blindspot_app/services/api_client.dart';
import 'package:blindspot_app/services/secure_store.dart';
import 'package:blindspot_app/services/token_store.dart';
import 'package:blindspot_app/theme/app_theme.dart';
import 'package:blindspot_app/widgets/big_action_tile.dart';

/// Stand-in for the real Profile screen, which lands in Task 12.
class ProfileStub extends StatelessWidget {
  const ProfileStub({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text(Copy.profileTitle)));
}

void main() {
  /// An [AuthProvider] whose cached session restores to signed-in with a
  /// known user — no network involved.
  Future<AuthProvider> signedInAuth({String name = 'Ana Cruz'}) async {
    final InMemorySecureStore store = InMemorySecureStore();
    final User user = User(
      id: 7,
      name: name,
      email: 'ana@example.com',
      contactNumber: '09171234567',
      createdAt: DateTime.utc(2026, 10, 18, 9, 30),
    );
    await store.write(TokenStore.storageKey, 'cached-token');
    await store.write(SessionRepository.userKey, jsonEncode(user.toJson()));
    final AuthProvider auth = AuthProvider(
      auth: MockAuthRepository(),
      session: SessionRepository(store),
      client: ApiClient(baseUrl: 'https://example.test'),
    );
    await auth.restoreSession();
    return auth;
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    required AuthProvider auth,
    double? textScale,
  }) {
    final Widget app = MaterialApp(
      theme: AppTheme.dark(),
      home: const HomeScreen(),
      routes: <String, WidgetBuilder>{
        '/profile': (_) => const ProfileStub(),
      },
    );
    return tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        // An override below the View's own MediaQuery wins for every
        // descendant, so text-scale tests are deterministic without
        // relying on platform-dispatcher round trips.
        child: textScale == null
            ? app
            : MediaQuery(
                data: MediaQueryData.fromView(tester.view)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: app,
              ),
      ),
    );
  }

  testWidgets(
      'shows the signed-in status strip, the Profile tile, and the '
      'future-features line', (tester) async {
    await pumpHome(tester, auth: await signedInAuth());

    expect(find.text(Copy.signedInAs('Ana Cruz')), findsOneWidget);
    expect(find.bySemanticsLabel(Copy.profileTitle), findsOneWidget);
    // The only working tile in Phase 1: no dead controls for blind users.
    expect(find.byType(BigActionTile), findsOneWidget);
    expect(find.text(Copy.home), findsOneWidget);
  });

  testWidgets('the status strip is a live region', (tester) async {
    await pumpHome(tester, auth: await signedInAuth());

    final SemanticsNode strip =
        tester.getSemantics(find.text(Copy.signedInAs('Ana Cruz')));
    expect(strip.flagsCollection.isLiveRegion, isTrue);
  });

  testWidgets('the Profile tile is a 56 dp button in semantics',
      (tester) async {
    await pumpHome(tester, auth: await signedInAuth());

    final Size size = tester.getSize(find.byType(BigActionTile));
    expect(size.height, greaterThanOrEqualTo(48.0));
    expect(size.width, greaterThanOrEqualTo(48.0));
    // Pinned by spec §5.3: tiles are 56 dp high at 1x.
    expect(size.height, 56.0);

    final SemanticsNode tile =
        tester.getSemantics(find.bySemanticsLabel(Copy.profileTitle));
    expect(tile.flagsCollection.isButton, isTrue);
  });

  testWidgets('the Profile tile navigates to /profile', (tester) async {
    await pumpHome(tester, auth: await signedInAuth());

    await tester.tap(find.bySemanticsLabel(Copy.profileTitle));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileStub), findsOneWidget);
  });

  testWidgets('no overflow at text scales from 1.0x to 3.0x on a small '
      '320x568 screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final double scale in const <double>[1.0, 1.5, 2.0, 3.0]) {
      await pumpHome(tester, auth: await signedInAuth(), textScale: scale);

      expect(
        tester.takeException(),
        isNull,
        reason: 'text scale $scale overflows the 320x568 screen',
      );
    }
  });

  testWidgets('the Profile tile grows with text scale and keeps its touch '
      'target at 3x', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final AuthProvider auth = await signedInAuth();
    await pumpHome(tester, auth: auth, textScale: 1.0);
    final double height1x = tester.getSize(find.byType(BigActionTile)).height;
    expect(height1x, 56.0);
    expect(tester.takeException(), isNull);

    await pumpHome(tester, auth: auth, textScale: 3.0);
    expect(
      tester.takeException(),
      isNull,
      reason: 'the tile label must lay out fully instead of overflowing',
    );

    final Size grown = tester.getSize(find.byType(BigActionTile));
    expect(grown.height, greaterThanOrEqualTo(48.0));
    // Grows past the fixed 1x height: the scaled label is not clipped.
    expect(grown.height, greaterThan(height1x));
  });
}
