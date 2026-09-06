import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/core/constants/clan_theme_colors.dart';
import 'package:clan_ai/data/models/app_theme_mode.dart';
import 'package:clan_ai/data/models/custom_theme_colors.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';

/// Theme section for SettingsScreen.
/// Placed at the bottom of settings in both assistant and roleplay modes.
class ThemeSection extends StatelessWidget {
  const ThemeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsVM = context.watch<SettingsViewModel>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Theme',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.accentPrimary,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<AppThemeMode>(
          segments: const [
            ButtonSegment(
              value: AppThemeMode.dark,
              label: Text('Dark'),
              icon: Icon(Icons.dark_mode_rounded, size: 16),
            ),
            ButtonSegment(
              value: AppThemeMode.light,
              label: Text('Light'),
              icon: Icon(Icons.light_mode_rounded, size: 16),
            ),
            ButtonSegment(
              value: AppThemeMode.custom,
              label: Text('Custom'),
              icon: Icon(Icons.palette_rounded, size: 16),
            ),
          ],
          selected: {settingsVM.themeMode},
          onSelectionChanged: (selected) {
            settingsVM.setAppThemeMode(selected.first);
          },
        ),
        if (settingsVM.themeMode == AppThemeMode.custom) ...[
          const SizedBox(height: 12),
          _buildPresetSelector(context, settingsVM),
        ],
      ],
    );
  }

  Widget _buildPresetSelector(BuildContext context, SettingsViewModel settingsVM) {
    final presets = const [
      (_presetWarm, 'Warm'),
      (_presetCool, 'Cool'),
      (_presetPastel, 'Pastel'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preset Colors',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.clanTextMuted,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((preset) {
            final (colors, label) = preset;
            final isSelected = settingsVM.customThemeColors?.bg.value == colors.bg.value;
            return ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors.bg,
                      shape: BoxShape.circle,
                      border: Border.all(color: context.clanBorder),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(label, style: const TextStyle(fontSize: 12)),
                ],
              ),
              selected: isSelected,
              onSelected: (_) {
                settingsVM.setCustomThemeColors(colors);
              },
              selectedColor: AppTheme.accentPrimary.withValues(alpha: 0.2),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: settingsVM.customThemeColors != null
              ? () => settingsVM.clearCustomThemeColors()
              : null,
          icon: const Icon(Icons.restore_rounded, size: 16),
          label: const Text('Reset to Dark Defaults'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}

const CustomThemeColors _presetWarm = CustomThemeColors.warm;
const CustomThemeColors _presetCool = CustomThemeColors.cool;
const CustomThemeColors _presetPastel = CustomThemeColors.pastel;
