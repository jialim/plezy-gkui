import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focus_theme.dart';
import 'package:plezy/main.dart' as app;
import 'package:plezy/services/family_projector_profile.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/layout_constants.dart';

void main() {
  test('projector profile uses ten-foot sizing', () {
    expect(FamilyProjectorProfile.enabled, isTrue);
    expect(FamilyProjectorProfile.uiScale, 1.2);
    expect(40 * FamilyProjectorProfile.uiScale, greaterThanOrEqualTo(48));
    expect(TvLayoutConstants.scaleForHeight(900), 1);
    expect(FocusTheme.focusBorderWidth, 4);
    expect(FocusTheme.focusScale, 1.06);
    expect(FocusTheme.fullCardFocusScale, 1.07);
    expect(FocusTheme.playerControlFocusScale, 1.18);
  });

  test('projector palette stays highly legible on a low-contrast display', () {
    final theme = monoTheme(dark: true, oled: true);
    final scheme = theme.colorScheme;
    final muted = Color.alphaBlend(theme.textTheme.bodySmall!.color!, scheme.surface);

    expect(scheme.primary, const Color(0xFFFFD54F));
    expect(scheme.surface, const Color(0xFF242424));
    expect(_contrast(scheme.onSurface, scheme.surface), greaterThanOrEqualTo(7));
    expect(_contrast(muted, scheme.surface), greaterThanOrEqualTo(7));
    expect(_contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(7));
  });

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
  });
}

double _contrast(Color a, Color b) {
  final lighter = a.computeLuminance() > b.computeLuminance() ? a : b;
  final darker = identical(lighter, a) ? b : a;
  return (lighter.computeLuminance() + 0.05) / (darker.computeLuminance() + 0.05);
}
