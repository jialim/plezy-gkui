part of '../../main_gkui.dart';

class SettingsPane extends StatelessWidget {
  const SettingsPane({required this.controller, super.key});
  final GkuiController controller;

  static const languages = <String, String>{
    '': 'Automatic',
    'en': 'English',
    'ja': 'Japanese',
    'zh': 'Chinese',
    'ms': 'Malay',
  };

  static const subtitleLanguages = <String, String>{
    '': 'Automatic',
    'off': 'Off',
    'en': 'English',
    'ja': 'Japanese',
    'zh': 'Chinese',
    'ms': 'Malay',
  };

  @override
  Widget build(BuildContext context) {
    final value = controller.settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 30),
      children: <Widget>[
        const PageHeading(
            title: 'Playback settings',
            subtitle: 'Remembered for this head unit'),
        const SizedBox(height: 18),
        _SettingCard(
          title: 'Preferred audio',
          child: DropdownButton<String>(
            isExpanded: true,
            value: value.audioLanguage,
            items: languages.entries
                .map((entry) => DropdownMenuItem<String>(
                    value: entry.key, child: Text(entry.value)))
                .toList(),
            onChanged: (choice) => controller
                .updateSettings(value.copyWith(audioLanguage: choice ?? '')),
          ),
        ),
        _SettingCard(
          title: 'Preferred subtitles',
          child: DropdownButton<String>(
            isExpanded: true,
            value: value.subtitleLanguage,
            items: subtitleLanguages.entries
                .map((entry) => DropdownMenuItem<String>(
                    value: entry.key, child: Text(entry.value)))
                .toList(),
            onChanged: (choice) => controller
                .updateSettings(value.copyWith(subtitleLanguage: choice ?? '')),
          ),
        ),
        _SettingCard(
          title: 'Seek buttons',
          child: Wrap(spacing: 18, runSpacing: 8, children: <Widget>[
            _SecondsPicker(
              label: 'Back',
              value: value.seekBackSeconds,
              onChanged: (seconds) => controller
                  .updateSettings(value.copyWith(seekBackSeconds: seconds)),
            ),
            _SecondsPicker(
              label: 'Forward',
              value: value.seekForwardSeconds,
              onChanged: (seconds) => controller
                  .updateSettings(value.copyWith(seekForwardSeconds: seconds)),
            ),
          ]),
        ),
        SwitchListTile(
          title: const Text('Autoplay next episode',
              style: TextStyle(fontSize: 18)),
          subtitle: const Text('Continue automatically after an episode ends'),
          value: value.autoPlayNext,
          onChanged: (enabled) =>
              controller.updateSettings(value.copyWith(autoPlayNext: enabled)),
        ),
        _SettingCard(
          title: 'Skip intro / credits',
          child: DropdownButton<SkipMode>(
            isExpanded: true,
            value: value.skipMode,
            items: const <DropdownMenuItem<SkipMode>>[
              DropdownMenuItem(value: SkipMode.off, child: Text('Off')),
              DropdownMenuItem(
                  value: SkipMode.button, child: Text('Show a skip button')),
              DropdownMenuItem(
                  value: SkipMode.automatic, child: Text('Skip automatically')),
            ],
            onChanged: (choice) {
              if (choice != null) {
                controller.updateSettings(value.copyWith(skipMode: choice));
              }
            },
          ),
        ),
        _SettingCard(
          title: 'Play Next countdown',
          child: DropdownButton<int>(
            isExpanded: true,
            value: value.playNextCountdownSeconds,
            items: const <int>[0, 5, 10, 15, 30]
                .map((seconds) => DropdownMenuItem<int>(
                      value: seconds,
                      child: Text(
                          seconds == 0 ? 'Immediately' : '$seconds seconds'),
                    ))
                .toList(),
            onChanged: (seconds) {
              if (seconds != null) {
                controller.updateSettings(
                    value.copyWith(playNextCountdownSeconds: seconds));
              }
            },
          ),
        ),
        SwitchListTile(
          title: const Text('Show watched indicators',
              style: TextStyle(fontSize: 18)),
          subtitle: const Text('Display a check mark on watched titles'),
          value: value.showWatchedIndicators,
          onChanged: (enabled) => controller
              .updateSettings(value.copyWith(showWatchedIndicators: enabled)),
        ),
        _SettingCard(
          title: 'App updates',
          child: Row(children: <Widget>[
            const Expanded(
              child: Text(
                'Checks automatically. Downloads the signed APK directly—no USB drive.',
                style: TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: controller.checkingForUpdate ||
                      controller.installingUpdate
                  ? null
                  : () => offerGkuiUpdate(context, controller, silent: false),
              icon: controller.checkingForUpdate
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.system_update),
              label: const Text('Check now'),
            ),
          ]),
        ),
      ],
    );
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(children: <Widget>[
            SizedBox(
                width: 190,
                child: Text(title, style: const TextStyle(fontSize: 18))),
            Expanded(child: child),
          ]),
        ),
      );
}

class _SecondsPicker extends StatelessWidget {
  const _SecondsPicker(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('$label:', style: const TextStyle(fontSize: 17)),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: value,
            items: const <int>[5, 10, 15, 30, 60]
                .map((seconds) => DropdownMenuItem<int>(
                    value: seconds, child: Text('$seconds sec')))
                .toList(),
            onChanged: (seconds) {
              if (seconds != null) onChanged(seconds);
            },
          ),
        ],
      );
}
