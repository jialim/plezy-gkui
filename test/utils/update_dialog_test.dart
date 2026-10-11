import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/services/update_service.dart';
import 'package:plezy/utils/update_dialog.dart';

void main() {
  testWidgets('cancelling does not pop the settings page when the download fails during dismissal', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    final download = Completer<String>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: Builder(
                          builder: (settingsContext) => Column(
                            children: [
                              const Text('Settings page'),
                              TextButton(
                                onPressed: () => showUpdateAvailableDialog(
                                  settingsContext,
                                  {
                                    'latestVersion': 'Test 8',
                                    'currentVersion': 'Test 7',
                                    'releaseUrl': 'https://github.com/jialim/plezy-gkui/releases',
                                    'canInstall': true,
                                  },
                                  title: 'Update',
                                  dismissLabel: 'Later',
                                  xgimiDownloader: (info, {onProgress, cancellation}) => download.future,
                                ).ignore(),
                                child: const Text('Check updates'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .ignore(),
              child: const Text('Open settings'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download and install'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 10));
    download.completeError(XgimiUpdateCancelled());
    await tester.pumpAndSettle();
    expect(find.text('Settings page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
