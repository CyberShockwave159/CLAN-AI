import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';

/// Profile section widget for SettingsScreen.
/// Extracted to eliminate the 100+ line inline profile management code.
class ProfileSection extends StatelessWidget {
  const ProfileSection({super.key});

  void _showCreateProfileDialog(BuildContext context) {
    final nameController = TextEditingController(text: 'New Profile');
    final settingsVM = context.read<SettingsViewModel>();
    final conn = settingsVM.connectionDetails;
    final urlController = TextEditingController(text: conn?.baseUrl ?? defaultBaseUrl);
    final apiKeyController = TextEditingController(text: conn?.apiKey ?? '');
    ApiProtocol selectedProtocol = conn?.protocol ?? ApiProtocol.openAi;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => WillPopScope(
          onWillPop: () async {
            nameController.dispose();
            urlController.dispose();
            apiKeyController.dispose();
            return true;
          },
          child: AlertDialog(
            title: const Text('Create Server Profile'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Profile Name',
                      hintText: 'e.g. Home WiFi, Office, Cellular',
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlController,
                    decoration: const InputDecoration(
                      labelText: 'Server Base URL',
                      hintText: 'http://192.168.x.x:8080',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiKeyController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'API Key (Optional)',
                      hintText: 'sk-...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ApiProtocol>(
                    segments: const [
                      ButtonSegment(value: ApiProtocol.openAi, label: Text('OpenAI')),
                      ButtonSegment(value: ApiProtocol.llamaNative, label: Text('llama.cpp')),
                    ],
                    selected: {selectedProtocol},
                    onSelectionChanged: (selected) {
                      setState(() => selectedProtocol = selected.first);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final baseUrl = urlController.text.trim();
                  if (name.isEmpty || baseUrl.isEmpty) return;
                  settingsVM.createProfile(
                    name: name,
                    baseUrl: baseUrl,
                    apiKey: apiKeyController.text.trim().isEmpty ? null : apiKeyController.text.trim(),
                    protocol: selectedProtocol,
                  );
                  Navigator.of(ctx).pop();
                },
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context, ServerProfile profile) {
    final nameController = TextEditingController(text: profile.name);
    final urlController = TextEditingController(text: profile.baseUrl);
    final apiKeyController = TextEditingController(text: profile.apiKey ?? '');
    final settingsVM = context.read<SettingsViewModel>();
    ApiProtocol selectedProtocol = profile.protocol;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => WillPopScope(
          onWillPop: () async {
            nameController.dispose();
            urlController.dispose();
            apiKeyController.dispose();
            return true;
          },
          child: AlertDialog(
            title: const Text('Edit Server Profile'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Profile Name'),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlController,
                    decoration: const InputDecoration(labelText: 'Server Base URL'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiKeyController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'API Key (Optional)'),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ApiProtocol>(
                    segments: const [
                      ButtonSegment(value: ApiProtocol.openAi, label: Text('OpenAI')),
                      ButtonSegment(value: ApiProtocol.llamaNative, label: Text('llama.cpp')),
                    ],
                    selected: {selectedProtocol},
                    onSelectionChanged: (selected) {
                      setState(() => selectedProtocol = selected.first);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final baseUrl = urlController.text.trim();
                  if (name.isEmpty || baseUrl.isEmpty) return;
                  final updatedProfile = profile.copyWith(
                    name: name,
                    baseUrl: baseUrl,
                    apiKey: apiKeyController.text.trim().isEmpty ? null : apiKeyController.text.trim(),
                    protocol: selectedProtocol,
                  );
                  settingsVM.updateProfile(updatedProfile);
                  Navigator.of(ctx).pop();
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteProfileDialog(BuildContext context, String profileId, String profileName) {
    final settingsVM = context.read<SettingsViewModel>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Profile?'),
        content: Text('Are you sure you want to delete "$profileName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.statusError),
            onPressed: () {
              settingsVM.deleteProfile(profileId);
              Navigator.of(ctx).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settingsVM = context.watch<SettingsViewModel>();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: settingsVM.activeProfileId,
                decoration: InputDecoration(
                  labelText: 'Active Profile',
                  prefixIcon: const Icon(Icons.fingerprint_rounded, size: 20),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: settingsVM.profiles.map((profile) {
                  return DropdownMenuItem(
                    value: profile.id,
                    child: Text(
                      profile.name,
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    settingsVM.switchProfile(val);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: 'New Profile',
              onPressed: () => _showCreateProfileDialog(context),
            ),
          ],
        ),
        if (settingsVM.profiles.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'No profiles yet. Click + to create one.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ),
          )
        else
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: settingsVM.profiles.length,
              itemBuilder: (context, profileIndex) {
                final profile = settingsVM.profiles[profileIndex];
                final isActive = profile.id == settingsVM.activeProfileId;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => settingsVM.switchProfile(profile.id),
                    onLongPress: () => _showEditProfileDialog(context, profile),
                    child: Chip(
                      avatar: Icon(
                        Icons.fingerprint_rounded,
                        size: 16,
                        color: isActive ? AppTheme.accentPrimary : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                      ),
                      label: Text(
                        profile.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      onDeleted: () => _showDeleteProfileDialog(context, profile.id, profile.name),
                      deleteIconColor: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isActive
                              ? AppTheme.accentPrimary.withValues(alpha: 0.5)
                              : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                          width: isActive ? 1.5 : 1,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
