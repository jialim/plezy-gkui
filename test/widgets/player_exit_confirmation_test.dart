import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/widgets/video_controls/player_chrome_controller.dart';
import 'package:plezy/widgets/video_controls/video_controls.dart';

void main() {
  late DateTime now;
  late int exits;
  late int confirmations;
  late PlayerChromeController chrome;

  PlayerNavigationCoordinator coordinator({required bool confirm}) => PlayerNavigationCoordinator(
    chromeController: chrome,
    isPromptOpen: () => false,
    dismissPrompt: () {},
    isChromePresented: () => chrome.controlsPresented,
    exitFullscreenIfActive: () async => false,
    exitPlayer: () => exits++,
    navigateHome: () {},
    confirmExit: () => confirm,
    showExitConfirmation: () => confirmations++,
    clock: () => now,
  );

  setUp(() {
    now = DateTime(2026, 10, 11, 20);
    exits = 0;
    confirmations = 0;
    chrome = PlayerChromeController(initiallyVisible: false);
  });
  tearDown(() => chrome.dispose());

  test('with the controls hidden, one Back asks and a second Back stops', () {
    final navigation = coordinator(confirm: true);
    navigation.handle(PlayerNavigationKey.back);
    expect(exits, 0);
    expect(confirmations, 1);
    now = now.add(const Duration(seconds: 2));
    navigation.handle(PlayerNavigationKey.back);
    expect(exits, 1);
  });

  test('a second Back after the window only asks again', () {
    final navigation = coordinator(confirm: true);
    navigation.handle(PlayerNavigationKey.back);
    now = now.add(const Duration(seconds: 5));
    navigation.handle(PlayerNavigationKey.back);
    expect(exits, 0);
    expect(confirmations, 2);
  });

  test('without confirmation one Back still leaves, as upstream does', () {
    coordinator(confirm: false).handle(PlayerNavigationKey.back);
    expect(exits, 1);
    expect(confirmations, 0);
  });
}
