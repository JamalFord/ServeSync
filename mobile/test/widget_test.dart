import 'package:flutter_test/flutter_test.dart';
import 'package:servesync/main.dart';

void main() {
  testWidgets('ServeSync app launch smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ServeSyncApp());

    // Verify that the ServeSync brand title appears on the PIN keypad screen.
    expect(find.text('ServeSync'), findsOneWidget);
    expect(find.text('Restaurant Operating System'), findsOneWidget);
  });
}
