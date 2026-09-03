import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';

/// Safety & Convenience section for SettingsScreen.
class SafetySection extends StatelessWidget {
  const SafetySection({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsVM = context.watch<SettingsViewModel>();

    return Column(
      children: [
        SwitchListTile(
          title: const Text('Confirm Message Deletion'),
          subtitle: const Text('Show a confirmation dialog before deleting a message and all subsequent messages.'),
          value: settingsVM.config.confirmDeleteMessage,
          onChanged: (value) => settingsVM.toggleConfirmDeleteMessage(value),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: const Text('View Thinking'),
          subtitle: const Text('Request and stream model reasoning/thinking in an expandable block for compatible models.'),
          value: settingsVM.config.reasoning,
          onChanged: (value) => settingsVM.toggleReasoning(value),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }
}
