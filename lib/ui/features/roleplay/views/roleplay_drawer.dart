import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/core/utils/silly_tavern_card_parser.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/repositories/character_repository.dart';
import 'package:clan_ai/ui/features/roleplay/widgets/character_creation_wizard.dart';
import 'package:clan_ai/ui/features/roleplay/widgets/character_edit_dialog.dart';
import 'package:clan_ai/ui/features/roleplay/widgets/character_memories_dialog.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/roleplay_view_model.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
import 'package:clan_ai/ui/features/settings/views/settings_screen.dart';
import 'package:clan_ai/ui/shared/avatar_utils.dart';
import 'package:clan_ai/ui/shared/conversation_import.dart';
import 'package:clan_ai/ui/shared/widgets/aprox_help_dialog.dart';
import 'package:clan_ai/ui/shared/widgets/confirm_delete_dialog.dart';
import 'package:clan_ai/ui/shared/widgets/drawer_export_menu.dart';

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
      builder: (_) => CharacterEditDialog(character: character, repository: repo),
    ).then((value) => value ?? character);
  }

  void _showDeleteDialog(BuildContext context, CharacterProfile character) {
    showConfirmDeleteDialog(
      context,
      title: 'Delete Character?',
      content: Text('Are you sure you want to delete "${character.name}"? All associated memories will be lost.'),
      onConfirm: () async {
        context.read<CharacterRepository>().deleteCharacter(character.id);
        context.read<RoleplayViewModel>().deleteCharacter(character.id);
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  void _showThreadDeleteDialog(BuildContext context, ChatThread thread, RoleplayViewModel roleplayVM, String characterId) {
    final drawerState = context.findAncestorStateOfType<_RoleplayDrawerState>();
    showConfirmDeleteDialog(
      context,
      title: 'Delete Conversation?',
      content: Text('Are you sure you want to delete "${thread.title}"? This cannot be undone.'),
      onConfirm: () async {
        final wasActive = roleplayVM.activeThread?.id == thread.id;
        await roleplayVM.deleteThread(thread.id);
        if (drawerState != null) {
          drawerState._expandedCharacters.remove(characterId);
        }
        if (wasActive && drawerState?.mounted == true) {
          Navigator.of(drawerState!.context).pop();
        }
      },
    );
  }

  Future<void> _handleStartChat(BuildContext context, CharacterProfile character) async {
    final settingsVM = context.read<SettingsViewModel>();
    final roleplayVM = context.read<RoleplayViewModel>();
    await roleplayVM.startRoleplay(
      character,
      serverConfig: settingsVM.config,
      connection: settingsVM.connectionDetails,
      modelContextLength: settingsVM.getSelectedModelContextLength(),
    );
    // ignore: use_build_context_synchronously
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  /// Starts a brand-new conversation with [character]'s default greeting.
  /// Unlike [startRoleplay] (which resumes the most recent thread for the
  /// character), this always creates a fresh thread.
  Future<void> _handleNewConversation(BuildContext context, CharacterProfile character) async {
    final settingsVM = context.read<SettingsViewModel>();
    final roleplayVM = context.read<RoleplayViewModel>();
    await roleplayVM.startRoleplayWithGreeting(
      character,
      character.firstMessage,
      serverConfig: settingsVM.config,
      connection: settingsVM.connectionDetails,
      modelContextLength: settingsVM.getSelectedModelContextLength(),
    );
    // ignore: use_build_context_synchronously
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _handleImportChat(BuildContext context, CharacterProfile character) {
    return importConversationFromJsonFile(
      context,
      onImport: (thread, messages) =>
          context.read<RoleplayViewModel>().importThread(thread, messages, character.id),
    );
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
                     if (newCharacter != null) {
                       await roleplayVM.startRoleplay(
                         newCharacter,
                         serverConfig: settingsVM.config,
                         connection: settingsVM.connectionDetails,
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
                   if (result == null || result.files.isEmpty) return;
                   final picked = result.files.first;
                   // Web file pickers expose content bytes instead of a path.
                   if (picked.path == null && picked.bytes == null) return;

                   if (context.mounted) Navigator.of(context).pop();

                   try {
                     final content = picked.bytes != null
                         ? utf8.decode(picked.bytes!)
                         : await File(picked.path!).readAsString();
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
                     final updated = context.mounted ? await _showEditDialog(context, character, charRepo) : character;

                      await roleplayVM.startRoleplay(
                        updated,
                        serverConfig: settingsVM.config,
                        connection: settingsVM.connectionDetails,
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
                                                color: AvatarUtils.getColor(character.name),
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
                                                      AvatarUtils.getInitials(character.name),
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
                                      onSelected: (action) async {
                                        if (action == 'edit') {
                                          final repo = context.read<CharacterRepository>();
                                          final updated = context.mounted ? await _showEditDialog(context, character, repo) : character;
                                          final roleplayVM = context.mounted ? context.read<RoleplayViewModel>() : null;
                                          roleplayVM?.updateActiveCharacter(updated);
                                          if (mounted) {
                                            setState(() {});
                                          }
                                        } else if (action == 'delete') {
                                          _showDeleteDialog(context, character);
                                        } else if (action == 'toggle_favorite') {
                                          final repo = context.read<CharacterRepository>();
                                          await repo.updateCharacter(
                                            character.copyWith(isFavorite: !character.isFavorite),
                                          );
                                          if (mounted) {
                                            setState(() {});
                                          }
                                        } else if (action == 'manage_memories') {
                                          Navigator.of(context).pop();
                                          if (context.mounted) {
                                            showDialog(
                                              context: context,
                                              builder: (ctx) => CharacterMemoriesDialog(
                                                characterId: character.id,
                                                characterName: character.name,
                                              ),
                                            );
                                          }
                                        } else if (action == 'export_character') {
                                          Navigator.of(context).pop();
                                          final roleplayVM = context.read<RoleplayViewModel>();
                                          final path = await roleplayVM.exportCharacterWithRAG(character);
                                          if (path != null && context.mounted) showExportSuccess(context, path);
                                        }
                                      },
                                      itemBuilder: (ctx) => [
                                        const PopupMenuItem(value: 'toggle_favorite', child: Text('Toggle Favorite')),
                                        const PopupMenuItem(value: 'manage_memories', child: Text('Manage Memories')),
                                        const PopupMenuItem(value: 'export_character', child: Text('Export Character + Memories')),
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
                                future: roleplayVM.getThreadsForCharacter(character.id),
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
                                              _handleNewConversation(context, character);
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
                                         // Import chat entry
                                         Material(
                                           color: Colors.transparent,
                                           child: InkWell(
                                             onTap: () => _handleImportChat(context, character),
                                             child: Padding(
                                               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                               child: Row(
                                                 children: [
                                                   Icon(
                                                     Icons.import_export_rounded,
                                                     size: 16,
                                                     color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                                   ),
                                                   const SizedBox(width: 8),
                                                   Text(
                                                     'Import Chat',
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
                                                    if (isActive)
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
                                                            if (action == 'delete') {
                                                             Navigator.of(context).pop();
                                                             _showThreadDeleteDialog(context, thread, roleplayVM, character.id);
                                                          } else if (action == 'export_txt' || action == 'export_json') {
                                                            final format = action == 'export_txt' ? ExportFormat.txt : ExportFormat.json;
                                                            final path = roleplayVM.exportThread(format, thread: thread, characterName: character.name);
                                                            path.then((p) {
                                                              if (p != null && context.mounted) {
                                                                showExportSuccess(context, p);
                                                              }
                                                            });
                                                          }
                                                        },
                                                        itemBuilder: (ctx) => [
                                                          ...buildExportMenuItems(),
                                                          const PopupMenuDivider(),
                                                          const PopupMenuItem(
                                                            value: 'delete',
                                                            child: Row(
                                                              children: [
                                                                Icon(Icons.delete_forever, size: 18, color: AppTheme.statusError),
                                                                SizedBox(width: 8),
                                                                Text('Delete Conversation', style: TextStyle(color: AppTheme.statusError)),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
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
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, size: 20),
              title: const Text('Artifacts & /flags', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () => showAproxHelpDialog(context),
            ),
          ],
        ),
      ),
    );
  }
}
