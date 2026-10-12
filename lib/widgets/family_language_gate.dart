import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../services/family_projector_profile.dart';
import '../services/settings_mutation_service.dart';
import '../services/settings_service.dart';

/// The languages the family projector build offers, at first launch and in
/// General settings.
const familyProjectorLocales = [AppLocale.zh, AppLocale.zhHant, AppLocale.en];

/// On the first launch of the family projector build, asks for Chinese or
/// English before anything else, so sign-in already reads in the family's
/// language. The choice can be changed later under General settings.
class FamilyLanguageGate extends StatefulWidget {
  const FamilyLanguageGate({super.key, required this.child});

  final Widget child;

  @override
  State<FamilyLanguageGate> createState() => _FamilyLanguageGateState();
}

class _FamilyLanguageGateState extends State<FamilyLanguageGate> {
  late bool _chosen =
      !FamilyProjectorProfile.enabled ||
      (SettingsService.instanceOrNull?.read(SettingsService.familyProjectorLanguageChosen) ?? true);

  Future<void> _pick(AppLocale locale) async {
    final settings = SettingsService.instanceOrNull;
    if (settings == null) return;
    // The sentinel goes first: a locale change rebuilds the app root, and the
    // rebuilt gate must already see the choice as made.
    await settings.write(SettingsService.familyProjectorLanguageChosen, true);
    if (!mounted) return;
    setState(() => _chosen = true);
    await const SettingsMutationService().write(context, SettingsService.appLocale, locale);
  }

  @override
  Widget build(BuildContext context) =>
      _chosen ? widget.child : FamilyLanguagePicker(onPicked: (locale) => _pick(locale));
}

class FamilyLanguagePicker extends StatelessWidget {
  const FamilyLanguagePicker({super.key, required this.onPicked});

  final ValueChanged<AppLocale> onPicked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget choice(String label, AppLocale locale, {bool autofocus = false}) => SizedBox(
      width: 320,
      height: 96,
      child: FilledButton(
        autofocus: autofocus,
        onPressed: () => onPicked(locale),
        child: Text(label, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600)),
      ),
    );
    return Scaffold(
      body: Center(
        child: FocusTraversalGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Both languages on the one screen nobody has chosen a language for.
              Text('选择语言 · Choose language', style: theme.textTheme.headlineLarge),
              const SizedBox(height: 12),
              Text(
                '之后可在“设置 > 通用”中更改 · You can change this later in Settings > General',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  choice('中文', AppLocale.zh, autofocus: true),
                  const SizedBox(width: 40),
                  choice('English', AppLocale.en),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
