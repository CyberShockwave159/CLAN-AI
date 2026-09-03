import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
import 'package:clan_ai/ui/features/settings/views/parameter_tuning_sheet.dart';

/// Shared parameter sheet opener used by both ChatScreen and RoleplayScreen.
/// Eliminates duplicate `_openParameterSheet` methods.
void openParameterSheet(BuildContext context) {
  final settingsVM = context.read<SettingsViewModel>();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ParameterTuningSheet(
      initialParams: settingsVM.config.defaultParams,
      onSave: (newParams) => settingsVM.updateDefaultParams(newParams),
    ),
  );
}
