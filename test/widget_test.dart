import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/main.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  });

  testWidgets('DaVinciMedApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DaVinciMedApp());
    await tester.pump();

    expect(find.text('CromerCare'), findsWidgets);
    expect(find.text('Autentificare Pacient'), findsOneWidget);
    expect(find.text('Email'), findsWidgets);
    expect(find.text('Conectare'), findsOneWidget);
  });
}
