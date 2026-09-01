import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/core/utils/silly_tavern_card_parser.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/repositories/character_repository.dart';
import 'package:clan_ai/ui/features/roleplay/widgets/character_creation_wizard.dart';
import 'package:clan_ai/ui/features/roleplay/widgets/silly_tavern_import_dialog.dart';
import 'package:clan_ai/ui/features/roleplay/widgets/persona_template_dialog.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/persona_template_view_model.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/roleplay_view_model.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
import 'package:clan_ai/ui/features/settings/views/settings_screen.dart';

/// Sidebar for roleplay mode — shows a list of characters.
/// Mirrors ChatDrawer structure but displays characters instead of threads.
class RoleplayDrawer extends StatefulWidget {
  const RoleplayDrawer({super.key});

  @override
  State<RoleplayDrawer> createState() => _RoleplayDrawerState();
}

class _RoleplayDrawerState extends State<RoleplayDrawer> {
  String _searchQuery = '';
  final Set<String> _expandedCharacters = {};
  bool _showFavoritesOnly = false;

  void _toggleCharacterExpansion(String characterId) {
    setState(() {
      if (_expandedCharacters.contains(characterId)) {
        _expandedCharacters.remove(characterId);
      } else {
        _expandedCharacters.add(characterId);
      }
    });
  }

  Future<CharacterProfile> _showEditDialog(BuildContext context, CharacterProfile character, CharacterRepository repo) {
    return showDialog<CharacterProfile>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final nameCtrl = TextEditingController(text: character.name);
          final personalityCtrl = TextEditingController(text: character.personality);
          final firstMsgCtrl = TextEditingController(text: character.firstMessage);
          final settingCtrl = TextEditingController(text: character.setting ?? '');
          final userPersonaCtrl = TextEditingController(text: character.userPersona ?? '');
          final systemPromptCtrl = TextEditingController(text: character.systemPrompt ?? '');
          final postHistoryCtrl = TextEditingController(text: character.postHistoryInstructions ?? '');
          final alternateGreetingsCtrl = TextEditingController(text: character.alternateGreetings.join('\n'));
           final personaVM = ctx.watch<PersonaTemplateViewModel>();
          String? selectedTemplateId;
          Uint8List? avatarPreview;
          final displayAvatar = avatarPreview ?? character.avatarData;

           return AlertDialog(
             title: const Text('Edit Character'),
             content: SingleChildScrollView(
               child: Column(
                 mainAxisSize: MainAxisSize.min,
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Row(
                     children: [
                       GestureDetector(
                         onTap: () async {
                           final XFile? image = await ImagePicker().pickImage(source: ImageSource.gallery);
                           if (image != null) {
                             final bytes = await image.readAsBytes();
                             setState(() => avatarPreview = bytes);
                           }
                         },
                         child: Container(
                           width: 48,
                           height: 48,
                           decoration: BoxDecoration(
                             shape: BoxShape.circle,
                             color: _avatarColor(displayAvatar, isDark),
                             border: Border.all(color: AppTheme.accentPrimary.withValues(alpha: 0.4), width: 2),
                           ),
                           child: displayAvatar != null
                               ? ClipOval(child: Image.memory(displayAvatar, width: 48, height: 48, fit: BoxFit.cover))
                               : const Icon(Icons.camera_alt_rounded, size: 20, color: AppTheme.accentPrimary),
                         ),
                       ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () async {
                                final XFile? image = await ImagePicker().pickImage(source: ImageSource.gallery);
                                if (image != null) {
                                  final bytes = await image.readAsBytes();
                                  setState(() => avatarPreview = bytes);
                                }
                              },
                              icon: const Icon(Icons.image_rounded, size: 14),
                              label: const Text('Change'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant,
                                foregroundColor: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              ),
                            ),
                            if (avatarPreview != null || character.avatarData != null)
                              TextButton(
                                onPressed: () => setState(() => avatarPreview = null),
                                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                                child: const Text('Remove', style: TextStyle(fontSize: 11)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: personalityCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Personality'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: firstMsgCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'First Message'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: settingCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Setting (Optional)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: alternateGreetingsCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Alternate Greetings (One per line, Optional)',
                      hintText: 'One greeting per line',
                    ),
                  ),
                   const SizedBox(height: 8),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: userPersonaCtrl,
                      builder: (context, value, child) {
                        return TextField(
                          controller: userPersonaCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Your Persona (Optional)',
                            hintText: 'Describe your role in this roleplay',
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                   Row(
                     children: [
                       Expanded(
                         child: DropdownButtonFormField<String>(
                           value: selectedTemplateId,
                           decoration: InputDecoration(
                             labelText: 'Load Persona Template',
                             prefixIcon: const Icon(Icons.tag_rounded),
                             border: OutlineInputBorder(
                               borderRadius: BorderRadius.circular(12),
                             ),
                           ),
                           hint: const Text('Select a template...'),
                           items: [
                             const DropdownMenuItem<String>(
                               value: '',
                               child: Text('-- None --'),
                             ),
                              ...personaVM.templates.map((template) {
                               return DropdownMenuItem<String>(
                                 value: template.id,
                                 child: Text(template.name),
                               );
                             }),
                           ],
                              onChanged: (value) {
                              setState(() => selectedTemplateId = value);
                              if (value != null && value.isNotEmpty) {
                                final template = personaVM.getTemplateById(value);
                                if (template != null) {
                                  userPersonaCtrl.text = template.description;
                                  setState(() {});
                                }
                              }
                            },
                         ),
                       ),
                       const SizedBox(width: 8),
                       IconButton(
                         tooltip: 'Create new template',
                         icon: const Icon(Icons.add_circle_rounded),
                         onPressed: () async {
                           await showDialog<void>(
                             context: ctx,
                             builder: (_) => const PersonaTemplateDialog(),
                           );
                           setState(() {});
                         },
                       ),
                     ],
                   ),
                   const SizedBox(height: 8),
                   TextField(
                     controller: systemPromptCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'System Prompt Override (Optional)',
                      hintText: 'Use {{original}} to prepend to default prompt',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: postHistoryCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Post History Instructions (Optional)',
                      hintText: 'Additional instructions appended after AI responses',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(character),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  List<String> alternateGreetings = [];
                  final greetingsText = alternateGreetingsCtrl.text.trim();
                  if (greetingsText.isNotEmpty) {
                    alternateGreetings = greetingsText
                        .split('\n')
                        .map((g) => g.trim())
                        .where((g) => g.isNotEmpty)
                        .toList();
                  }

                  final updated = character.copyWith(
                    name: nameCtrl.text.trim().isEmpty ? character.name : nameCtrl.text.trim(),
                    personality: personalityCtrl.text.trim(),
                    firstMessage: firstMsgCtrl.text.trim(),
                    setting: settingCtrl.text.trim().isEmpty ? null : settingCtrl.text.trim(),
                    userPersona: userPersonaCtrl.text.trim().isEmpty ? null : userPersonaCtrl.text.trim(),
                    avatarData: avatarPreview,
                    systemPrompt: systemPromptCtrl.text.trim().isEmpty ? null : systemPromptCtrl.text.trim(),
                    postHistoryInstructions: postHistoryCtrl.text.trim().isEmpty ? null : postHistoryCtrl.text.trim(),
                    alternateGreetings: alternateGreetings,
                  );
                  repo.updateCharacter(updated);
                  Navigator.of(ctx).pop(updated);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    ).then((value) => value ?? character);
  }

  void _showDeleteDialog(BuildContext context, CharacterProfile character) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Character?'),
        content: Text('Are you sure you want to delete "${character.name}"? All associated memories will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.statusError),
            onPressed: () async {
              context.read<CharacterRepository>().deleteCharacter(character.id);
              context.read<RoleplayViewModel>().deleteCharacter(character.id);
              Navigator.of(ctx).pop();
              if (mounted) {
                setState(() {});
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Color _getAvatarColor(String name) {
    final colors = const [
      AppTheme.accentPrimary,
      AppTheme.accentSecondary,
      AppTheme.accentIndigo,
      AppTheme.accentCyan,
    ];
    final idx = name.codeUnitAt(0) % colors.length;
    return colors[idx];
  }

  Color _avatarColor(Uint8List? avatar, bool isDark) {
    return avatar != null ? Colors.transparent : (isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant);
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Future<void> _handleStartChat(BuildContext context, CharacterProfile character) async {
    final settingsVM = context.read<SettingsViewModel>();
    final roleplayVM = context.read<RoleplayViewModel>();
    await roleplayVM.startRoleplay(
      character,
      serverConfig: settingsVM.config,
      modelContextLength: settingsVM.getSelectedModelContextLength(),
    );
    // ignore: use_build_context_synchronously
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header with "New Roleplay" Action
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.theater_comedy_rounded, size: 20),
                label: const Text('New Roleplay', style: TextStyle(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                ),
                onPressed: () async {
                   final settingsVM = context.read<SettingsViewModel>();
                   final roleplayVM = context.read<RoleplayViewModel>();
                   Navigator.of(context).pop();
                   final newCharacter = await showDialog<CharacterProfile>(
                     context: context,
                     builder: (_) => const CharacterCreationWizard(),
                   );
                    if (mounted && newCharacter != null) {
                      await roleplayVM.startRoleplay(
                        newCharacter,
                        serverConfig: settingsVM.config,
                        modelContextLength: settingsVM.getSelectedModelContextLength(),
                      );
                    }
                 },
              ),
            ),

            // Import SillyTavern Card button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.import_export_rounded, size: 20),
                label: const Text('Import ST Card', style: TextStyle(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                ),
                onPressed: () async {
                   final charRepo = context.read<CharacterRepository>();
                   final settingsVM = context.read<SettingsViewModel>();
                   final roleplayVM = context.read<RoleplayViewModel>();

                   final result = await FilePicker.platform.pickFiles(
                     type: FileType.custom,
                     allowedExtensions: ['json'],
                     allowMultiple: false,
                   );
                   if (result == null || result.files.isEmpty || result.files.first.path == null) return;

                   Navigator.of(context).pop();

                   try {
                     final content = await File(result.files.first.path!).readAsString();
                     final json = jsonDecode(content) as Map<String, dynamic>;
                     final parsed = ParsedCharacterCard.fromJson(json);

                     if (!parsed.isValid) {
                       if (context.mounted) {
                         ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('Not a valid SillyTavern character card (chara_card_v2)')),
                         );
                       }
                       return;
                     }

                     final character = CharacterProfile(
                       name: parsed.name,
                       personality: parsed.personality,
                       firstMessage: parsed.firstMessage,
                       setting: parsed.setting,
                       userPersona: parsed.userPersona,
                     );

                     await charRepo.createCharacter(character);

                     // Auto-open edit dialog for the imported character
                     final updated = await _showEditDialog(context, character, charRepo);

                     await roleplayVM.startRoleplay(
                       updated,
                       serverConfig: settingsVM.config,
                       modelContextLength: settingsVM.getSelectedModelContextLength(),
                     );

                     if (context.mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('Character imported')),
                       );
                     }
                   } catch (e) {
                     if (context.mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(content: Text('Import failed: $e')),
                       );
                     }
                   }
                 },
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'Search characters...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: _showFavoritesOnly ? 'Show all characters' : 'Show favorites only',
                    child: IconButton(
                      icon: Icon(
                        Icons.star_rounded,
                        size: 20,
                        color: _showFavoritesOnly
                            ? AppTheme.accentSecondary
                            : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                      ),
                      onPressed: () => setState(() => _showFavoritesOnly = !_showFavoritesOnly),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Character List
            Expanded(
              child: FutureBuilder<List<CharacterProfile>>(
                future: context.read<CharacterRepository>().getAllCharacters(),
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.theater_comedy_outlined,
                            size: 48,
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No characters yet',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final filtered = snapshot.data!
                      .where((c) => _searchQuery.isEmpty || c.name.toLowerCase().contains(_searchQuery.toLowerCase()))
                      .where((c) => !_showFavoritesOnly || c.isFavorite)
                      .toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        'No matching characters',
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          fontSize: 14,
                        ),
                      ),
                    );
                  }

                    return ListView.builder(
                      itemCount: filtered.length,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemBuilder: (context, index) {
                        final character = filtered[index];
                        final isExpanded = _expandedCharacters.contains(character.id);
                        final roleplayVM = context.read<RoleplayViewModel>();
                        final activeThreadId = roleplayVM.activeThread?.id;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark ? AppTheme.darkSurfaceVariant.withValues(alpha: 0.5) : AppTheme.lightSurfaceVariant,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: Row(
                                  children: [
                                    // Avatar
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: GestureDetector(
                                        onTap: () => _handleStartChat(context, character),
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Container(
                                              width: 42,
                                              height: 42,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: _getAvatarColor(character.name),
                                              ),
                                              child: character.avatarData != null
                                                  ? ClipOval(
                                                      child: Image.memory(
                                                        character.avatarData!,
                                                        width: 42,
                                                        height: 42,
                                                        fit: BoxFit.cover,
                                                      ),
                                                    )
                                                  : Text(
                                                      _getInitials(character.name),
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w700,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                            ),
                                            if (character.isFavorite)
                                              Positioned(
                                                right: -2,
                                                bottom: -2,
                                                child: Icon(
                                                  Icons.star_rounded,
                                                  size: 14,
                                                  color: AppTheme.accentSecondary,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    // Name
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          if (_expandedCharacters.contains(character.id)) {
                                            _toggleCharacterExpansion(character.id);
                                          } else {
                                            _handleStartChat(context, character);
                                          }
                                        },
                                        child: Text(
                                          character.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Expand/Collapse indicator
                                    GestureDetector(
                                      onTap: () => _toggleCharacterExpansion(character.id),
                                      child: Icon(
                                        isExpanded
                                            ? Icons.keyboard_arrow_down_rounded
                                            : Icons.chevron_right_rounded,
                                        size: 18,
                                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                      ),
                                    ),

                                    // Actions
                                    PopupMenuButton<String>(
                                      icon: Icon(
                                        Icons.more_vert_rounded,
                                        size: 18,
                                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                      ),
                                      onSelected: (action) {
                                        if (action == 'edit') {
                                          _showEditDialog(context, character, context.read<CharacterRepository>());
                                        } else if (action == 'delete') {
                                          _showDeleteDialog(context, character);
                                        } else if (action == 'toggle_favorite') {
                                          final repo = context.read<CharacterRepository>();
                                          repo.updateCharacter(
                                            character.copyWith(isFavorite: !character.isFavorite),
                                          );
                                        }
                                      },
                                      itemBuilder: (ctx) => [
                                        const PopupMenuItem(value: 'toggle_favorite', child: Text('Toggle Favorite')),
                                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.statusError),
                                              SizedBox(width: 8),
                                              Text('Delete', style: TextStyle(color: AppTheme.statusError)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Expanded thread list
                            if (isExpanded)
                              FutureBuilder<List<ChatThread>>(
                                future: roleplayVM.getCachedThreadsForCharacter(character.id),
                                builder: (ctx, snapshot) {
                                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                                    return const SizedBox.shrink();
                                  }

                                  final threads = snapshot.data!;
                                  return Container(
                                    margin: const EdgeInsets.only(left: 16, bottom: 4),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppTheme.darkSurfaceVariant.withValues(alpha: 0.3)
                                          : AppTheme.lightSurfaceVariant.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        // New conversation entry
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () {
                                              _handleStartChat(context, character);
                                              _toggleCharacterExpansion(character.id);
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.add_rounded,
                                                    size: 16,
                                                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'New Conversation',
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      fontStyle: FontStyle.italic,
                                                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const Divider(height: 1),
                                         // Existing threads
                                         ...threads.map((thread) {
                                           final isActive = thread.id == activeThreadId;
                                           final hasBranchParent = thread.branchFromThreadId != null;
                                           // Find parent thread title if this is a branch
                                           String? branchParentTitle;
                                           if (hasBranchParent) {
                                             final parentThread = threads.firstWhere(
                                               (t) => t.id == thread.branchFromThreadId,
                                               orElse: () => thread,
                                             );
                                             branchParentTitle = parentThread.title;
                                           }
                                           return Material(
                                             color: Colors.transparent,
                                             child: InkWell(
                                               onTap: () {
                                                 roleplayVM.selectThread(thread);
                                                 Navigator.of(context).pop();
                                               },
                                               child: Padding(
                                                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                 child: Row(
                                                   children: [
                                                     Icon(
                                                       hasBranchParent
                                                           ? Icons.call_split_rounded
                                                           : Icons.chat_bubble_outline_rounded,
                                                       size: 16,
                                                       color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                                     ),
                                                     const SizedBox(width: 8),
                                                     Expanded(
                                                       child: Column(
                                                         crossAxisAlignment: CrossAxisAlignment.start,
                                                         children: [
                                                           Text(
                                                             thread.title,
                                                             maxLines: 1,
                                                             overflow: TextOverflow.ellipsis,
                                                             style: TextStyle(
                                                               fontSize: 12.5,
                                                               fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                                                               color: isActive
                                                                   ? AppTheme.accentPrimary
                                                                   : (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary),
                                                             ),
                                                           ),
                                                           if (hasBranchParent && branchParentTitle != null)
                                                             Text(
                                                               'Branch of: $branchParentTitle',
                                                               maxLines: 1,
                                                               overflow: TextOverflow.ellipsis,
                                                               style: TextStyle(
                                                                 fontSize: 10,
                                                                 fontStyle: FontStyle.italic,
                                                                 color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                                               ),
                                                             ),
                                                         ],
                                                       ),
                                                     ),
                                                    if (isActive) ...[
                                                      Icon(
                                                        Icons.check_rounded,
                                                        size: 14,
                                                        color: AppTheme.accentPrimary,
                                                      ),
                                                      PopupMenuButton<String>(
                                                        icon: Icon(
                                                          Icons.more_vert_rounded,
                                                          size: 14,
                                                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                                        ),
                                                        onSelected: (action) {
                                                          if (action == 'export_txt' || action == 'export_json') {
                                                            final format = action == 'export_txt' ? ExportFormat.txt : ExportFormat.json;
                                                            final path = roleplayVM.exportThread(format);
                                                            path.then((p) {
                                                              if (p != null && context.mounted) {
                                                                // ignore: use_build_context_synchronously
                                                                ScaffoldMessenger.of(context).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text('Exported to $p'),
                                                                    duration: const Duration(seconds: 3),
                                                                    behavior: SnackBarBehavior.floating,
                                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                                  ),
                                                                );
                                                              }
                                                            });
                                                          }
                                                        },
                                                        itemBuilder: (ctx) => [
                                                          const PopupMenuItem(
                                                            value: 'export_txt',
                                                            child: Row(
                                                              children: [
                                                                Icon(Icons.file_copy_outlined, size: 18),
                                                                SizedBox(width: 8),
                                                                Text('Export as TXT'),
                                                              ],
                                                            ),
                                                          ),
                                                          const PopupMenuItem(
                                                            value: 'export_json',
                                                            child: Row(
                                                              children: [
                                                                Icon(Icons.code_outlined, size: 18),
                                                                SizedBox(width: 8),
                                                                Text('Export as JSON'),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  );
                                },
                              ),

                            const Divider(height: 1, indent: 8, endIndent: 8),
                          ],
                        );
                      },
                    );
                },
              ),
            ),

            const Divider(height: 1),

            // Footer with Settings Action
            ListTile(
              leading: const Icon(Icons.settings_outlined, size: 20),
              title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
