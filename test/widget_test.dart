import 'package:flutter_test/flutter_test.dart';
import 'package:chennai_bus_crowding/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ChennaiApp());
    expect(find.byType(ChennaiApp), findsOneWidget);
  });
}
