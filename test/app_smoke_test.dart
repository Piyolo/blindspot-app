import 'package:flutter_test/flutter_test.dart';
import 'package:blindspot_app/main.dart';
import 'package:blindspot_app/screens/home_screen.dart';

void main() {
  testWidgets('app boots to splash then navigates to home', (tester) async {
    await tester.pumpWidget(const BlindSpotApp());
    expect(find.text('BlindSpot'), findsWidgets);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
