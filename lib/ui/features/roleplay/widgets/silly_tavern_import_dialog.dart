import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/core/utils/st_avatar_downloader.dart';
import 'package:clan_ai/core/utils/silly_tavern_card_parser.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/models/persona_template.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/persona_template_view_model.dart';
import 'package:clan_ai/ui/features/roleplay/widgets/persona_template_dialog.dart';

/// Preview dialog for SillyTavern character card imports.
///
/// Displays parsed fields from the card and allows the user to edit
/// them before confirming the import. Returns the final CharacterProfile
/// on confirmation, or null if cancelled.
class SillyTavernImportDialog extends StatefulWidget {
  final ParsedCharacterCard card;
  final String sourceFilename;

  const SillyTavernImportDialog({
    super.key,
    required this.card,
    required this.sourceFilename,
  });

  @override
  State<SillyTavernImportDialog> createState() => _SillyTavernImportDialogState();
}

class _SillyTavernImportDialogState extends State<SillyTavernImportDialog> {
  late TextEditingController _nameController;
  late TextEditingController _personalityController;
  late TextEditingController _firstMessageController;
  late TextEditingController _settingController;
  late TextEditingController _userPersonaController;
  late TextEditingController _systemPromptController;
  late TextEditingController _postHistoryController;
  late TextEditingController _alternateGreetingsController;
  String? _selectedTemplateId;
  Uint8List? _avatarBytes;
  bool _avatarLoading = false;
  bool _avatarFailed = false;
  bool _canImport = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.card.name);
    _personalityController = TextEditingController(text: widget.card.personality);
    _firstMessageController = TextEditingController(text: widget.card.firstMessage);
    _settingController = TextEditingController(text: widget.card.setting ?? '');
    _userPersonaController = TextEditingController(text: widget.card.userPersona ?? '');
    _systemPromptController = TextEditingController(text: widget.card.systemPrompt ?? '');
    _postHistoryController = TextEditingController(text: widget.card.postHistoryInstructions ?? '');
    _alternateGreetingsController = TextEditingController(text: widget.card.alternateGreetings.join('\n'));
    _validateFields();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _personalityController.dispose();
    _firstMessageController.dispose();
    _settingController.dispose();
    _userPersonaController.dispose();
    _systemPromptController.dispose();
    _postHistoryController.dispose();
    _alternateGreetingsController.dispose();
    super.dispose();
  }

  void _applyTemplate(PersonaTemplate template) {
    setState(() {
      _selectedTemplateId = template.id;
      _userPersonaController.text = template.description;
    });
  }

  void _validateFields() {
    setState(() {
      _canImport = _nameController.text.trim().isNotEmpty &&
          _personalityController.text.trim().isNotEmpty &&
          _firstMessageController.text.trim().isNotEmpty;
    });
  }

  Future<void> _fetchAvatar() async {
    if (widget.card.avatarUrl == null || widget.card.avatarUrl!.isEmpty) return;

    setState(() {
      _avatarLoading = true;
      _avatarFailed = false;
      _avatarBytes = null;
    });

    final downloader = StAvatarDownloader();
    try {
      final bytes = await downloader.downloadAvatar(widget.card.avatarUrl!);
      if (mounted && bytes != null) {
        setState(() => _avatarBytes = bytes);
      } else if (mounted) {
        setState(() => _avatarFailed = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _avatarFailed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _avatarLoading = false);
      }
    }
  }

  CharacterProfile _buildCharacter() {
    List<String> alternateGreetings = [];
    final greetingsText = _alternateGreetingsController.text.trim();
    if (greetingsText.isNotEmpty) {
      alternateGreetings = greetingsText
          .split('\n')
          .map((g) => g.trim())
          .where((g) => g.isNotEmpty)
          .toList();
    }

    return CharacterProfile(
      name: _nameController.text.trim(),
      personality: _personalityController.text.trim(),
      firstMessage: _firstMessageController.text.trim(),
      setting: _settingController.text.trim().isEmpty ? null : _settingController.text.trim(),
      userPersona: _userPersonaController.text.trim().isEmpty ? null : _userPersonaController.text.trim(),
      avatarData: _avatarBytes,
      systemPrompt: _systemPromptController.text.trim().isEmpty ? null : _systemPromptController.text.trim(),
      postHistoryInstructions: _postHistoryController.text.trim().isEmpty ? null : _postHistoryController.text.trim(),
      alternateGreetings: alternateGreetings,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final personaVM = context.watch<PersonaTemplateViewModel>();

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 750),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  const Text(
                    'Import SillyTavern Card',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    widget.sourceFilename,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar preview
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _fetchAvatar,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _avatarBytes != null ? Colors.transparent : (isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant),
                              border: Border.all(
                                color: AppTheme.accentPrimary.withValues(alpha: 0.4),
                                width: 2,
                              ),
                            ),
                            child: _buildAvatarContent(isDark),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Tap to fetch avatar from source',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Name
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Character Name *',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                      onChanged: (_) => _validateFields(),
                    ),
                    const SizedBox(height: 12),

                    // Personality
                    TextField(
                      controller: _personalityController,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Personality / Description *',
                        prefixIcon: Icon(Icons.psychology_rounded),
                      ),
                      onChanged: (_) => _validateFields(),
                    ),
                    const SizedBox(height: 12),

                    // First message
                    TextField(
                      controller: _firstMessageController,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'First Message *',
                        prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                      ),
                      onChanged: (_) => _validateFields(),
                    ),
                    const SizedBox(height: 12),

                    // Setting
                    TextField(
                      controller: _settingController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Setting / Scenario',
                        prefixIcon: const Icon(Icons.map_rounded),
                        helperText: 'Optional',
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Alternate greetings
                    TextField(
                      controller: _alternateGreetingsController,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: 'Alternate First Messages',
                        hintText: 'One greeting per line',
                        prefixIcon: const Icon(Icons.chat_rounded),
                        helperText: 'Optional',
                      ),
                    ),
                    const SizedBox(height: 12),

                    // User persona
                    TextField(
                      controller: _userPersonaController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Your Persona',
                        prefixIcon: const Icon(Icons.account_circle_rounded),
                        helperText: 'Optional',
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Persona template selector
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedTemplateId,
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
                              setState(() => _selectedTemplateId = value);
                              if (value != null && value.isNotEmpty) {
                                final template = personaVM.getTemplateById(value);
                                if (template != null) {
                                  _applyTemplate(template);
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
                              context: context,
                              builder: (_) => const PersonaTemplateDialog(),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Divider + Advanced settings header
                    Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Advanced Prompt Settings (optional)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // System prompt override
                    TextField(
                      controller: _systemPromptController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Character System Prompt',
                        hintText: 'Override the default system prompt. Use {{original}} to prepend to default.',
                        prefixIcon: const Icon(Icons.psychology_alt_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Post history instructions
                    TextField(
                      controller: _postHistoryController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Post History Instructions',
                        hintText: 'Additional instructions after AI responses',
                        prefixIcon: const Icon(Icons.history_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _canImport ? () => Navigator.of(context, rootNavigator: true).pop(_buildCharacter()) : null,
                    child: const Text('Import'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarContent(bool isDark) {
    if (_avatarLoading) {
      return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_avatarFailed) {
      return Icon(Icons.broken_image_rounded, size: 24, color: AppTheme.statusError);
    }
    if (_avatarBytes != null) {
      return ClipOval(
        child: Image.memory(_avatarBytes!, width: 64, height: 64, fit: BoxFit.cover),
      );
    }
    return Icon(Icons.image_rounded, size: 24, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted);
  }
}
