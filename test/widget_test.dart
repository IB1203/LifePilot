import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/main.dart';

void main() {
  testWidgets('LifePilot AI launches successfully', (tester) async {
    final store =
        LifePilotStore.inMemory(clock: () => DateTime(2026, 10, 29, 9, 30));
    await tester.pumpWidget(LifePilotApp(store: store));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('Thursday, 29 October 2026'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Finance'), findsOneWidget);
    expect(find.text('Tasks'), findsWidgets);
    expect(find.text('Assistant'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });
}
