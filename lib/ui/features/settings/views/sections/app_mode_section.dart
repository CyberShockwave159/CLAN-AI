import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/data/models/app_mode.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';

/// App Mode toggle section for SettingsScreen.
class AppModeSection extends StatelessWidget {
  const AppModeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsVM = context.watch<SettingsViewModel>();

    return SwitchListTile(
      title: const Text('Roleplay Mode'),
      subtitle: const Text('Enable character roleplay with persistent memory.'),
      value: settingsVM.appMode == AppMode.roleplay,
      onChanged: (value) {
        settingsVM.updateAppMode(
          value ? AppMode.roleplay : AppMode.assistant,
        );
        Navigator.of(context).pop();
      },
      contentPadding: EdgeInsets.zero,
    );
  }
}
