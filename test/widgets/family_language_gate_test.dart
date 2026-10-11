// Run with --dart-define=FAMILY_PROJECTOR_MODE=true (see xgimi-lite.yml).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/services/family_projector_profile.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/widgets/family_language_gate.dart';

import '../test_helpers/prefs.dart';

void main() {
  final enabled = FamilyProjectorProfile.enabled;

  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
    await LocaleSettings.setLocale(AppLocale.zh);
  });

  Future<void> pumpGate(WidgetTester tester) =>
      tester.pumpWidget(const MaterialApp(home: FamilyLanguageGate(child: Text('app'))));

  testWidgets('the first launch asks for a language before the app', (tester) async {
    await pumpGate(tester);
    expect(find.text('app'), findsNothing);
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('app'), findsOneWidget);
    final settings = SettingsService.instanceOrNull!;
    expect(settings.read(SettingsService.appLocale), AppLocale.en);
    expect(settings.read(SettingsService.familyProjectorLanguageChosen), isTrue);
  }, skip: !enabled);

  testWidgets('a language chosen once is not asked for again', (tester) async {
    await SettingsService.instanceOrNull!.write(SettingsService.familyProjectorLanguageChosen, true);
    await pumpGate(tester);
    expect(find.text('app'), findsOneWidget);
    expect(find.text('English'), findsNothing);
  }, skip: !enabled);

  test('settings offer only the household languages', () {
    expect(familyProjectorLocales, [AppLocale.zh, AppLocale.zhHant, AppLocale.en]);
  });
}
