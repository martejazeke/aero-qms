import 'package:aero/main.dart';
import 'package:aero/services/database_service.dart';
import 'package:aero/services/queue_service.dart';
import 'package:aero/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('AeroApp shows empty home screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseService.init();

    final settings = SettingsService();
    await settings.init();

    final queue = QueueService();
    queue.attachSettings(settings);
    await queue.loadFromDatabase();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: queue),
        ],
        child: const AeroApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No sessions yet'), findsOneWidget);
    expect(find.text('New Session'), findsOneWidget);
  });
}
