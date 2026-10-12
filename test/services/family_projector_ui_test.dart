import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/widgets/side_navigation_rail.dart';
import 'package:plezy/focus/focus_theme.dart';
import 'package:plezy/main.dart' as app;
import 'package:plezy/services/family_projector_profile.dart';
import 'package:plezy/services/settings_service.dart' hide ThemeMode;
import '../test_helpers/prefs.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/layout_constants.dart';

void main() {
  // Runs in the XGIMI build check, which sets FAMILY_PROJECTOR_MODE=true.
  const skip = !FamilyProjectorProfile.enabled;

  test('projector profile uses ten-foot sizing', () {
    expect(FamilyProjectorProfile.enabled, isTrue);
    expect(FamilyProjectorProfile.uiScale, 1.2);
    expect(40 * FamilyProjectorProfile.uiScale, greaterThanOrEqualTo(48));
    expect(TvLayoutConstants.scaleForHeight(900), 1);
    expect(FocusTheme.focusBorderWidth, 4);
    expect(FocusTheme.focusScale, 1.06);
    expect(FocusTheme.fullCardFocusScale, 1.07);
    expect(FocusTheme.playerControlFocusScale, 1.18);
    expect(FamilyProjectorProfile.shouldOfferPlayFromBeginning(null), isFalse);
    expect(FamilyProjectorProfile.shouldOfferPlayFromBeginning(0), isFalse);
    expect(FamilyProjectorProfile.shouldOfferPlayFromBeginning(90 * 1000), isTrue);
  }, skip: skip);

  testWidgets('selected size enlarges controls without the TV scale cancelling it', (tester) async {
    resetSharedPreferencesForTest();
    final settings = await SettingsService.getInstance();
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var media = const MediaQueryData();
    var tvScale = 0.0;
    await tester.pumpWidget(
      MaterialApp(
        home: app.FormFactorScale(
          child: Builder(
            builder: (context) {
              media = MediaQuery.of(context);
              tvScale = TvLayoutConstants.scaleOf(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    for (final size in ProjectorUiSize.values) {
      await settings.write(SettingsService.projectorUiSize, size);
      await tester.pump();
      final scale = FamilyProjectorProfile.scaleFor(size);
      expect(media.size.width, closeTo(1920 / scale, 0.01));
      expect(media.size.height, closeTo(1080 / scale, 0.01));
      expect(tvScale, closeTo(1, 0.01));
    }
  }, skip: skip);

  test('projector palette stays highly legible on a low-contrast display', () {
    final theme = monoTheme(dark: true, oled: true);
    final scheme = theme.colorScheme;
    final muted = Color.alphaBlend(theme.textTheme.bodySmall!.color!, scheme.surface);

    expect(scheme.primary, const Color(0xFFFFD54F));
    expect(scheme.surface, const Color(0xFF242424));
    expect(_contrast(scheme.onSurface, scheme.surface), greaterThanOrEqualTo(7));
    expect(_contrast(muted, scheme.surface), greaterThanOrEqualTo(7));
    expect(_contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(7));
  }, skip: skip);

  testWidgets('projector root enlarges a 1080p logical surface by 1.2x', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var media = const MediaQueryData();
    await tester.pumpWidget(
      MaterialApp(
        home: app.FormFactorScale(
          child: Builder(
            builder: (context) {
              media = MediaQuery.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    expect(media.size, const Size(1600, 900));
    expect(media.devicePixelRatio, 1.2);
  }, skip: skip);

  testWidgets('library rail focus is an amber outline, not a faint white tint', (tester) async {
    final focus = FocusNode();
    final other = FocusNode();
    addTearDown(focus.dispose);
    addTearDown(other.dispose);
    final theme = monoTheme(dark: true);
    await tester.pumpWidget(
      InputModeTracker(
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                NavigationRailItem(
                  icon: Symbols.movie_rounded,
                  label: const Text('Movies'),
                  isSelected: false,
                  onTap: () {},
                  focusNode: focus,
                ),
                NavigationRailItem(
                  icon: Symbols.tv_rounded,
                  label: const Text('Shows'),
                  isSelected: true,
                  onTap: () {},
                  focusNode: other,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    focus.requestFocus();
    await tester.pumpAndSettle();

    final amber = theme.colorScheme.primary;
    final outlined = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.foregroundDecoration)
        .whereType<BoxDecoration>()
        .where((d) => d.border is Border && (d.border! as Border).top.color == amber);
    expect(outlined, hasLength(1), reason: 'only the focused item is outlined in amber');
    final fills = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.color)
        .whereType<Color>()
        .toList();
    expect(fills, contains(amber.withValues(alpha: 0.3)));
    expect(fills, contains(amber.withValues(alpha: 0.14)));
  }, skip: !FamilyProjectorProfile.enabled);
}

double _contrast(Color a, Color b) {
  final lighter = a.computeLuminance() > b.computeLuminance() ? a : b;
  final darker = identical(lighter, a) ? b : a;
  return (lighter.computeLuminance() + 0.05) / (darker.computeLuminance() + 0.05);
}
