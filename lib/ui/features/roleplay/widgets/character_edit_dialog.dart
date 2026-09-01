import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/models/persona_template.dart';
import 'package:clan_ai/data/repositories/character_repository.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/persona_template_view_model.dart';
import 'package:clan_ai/ui/features/roleplay/widgets/persona_template_dialog.dart';

/// Dialog for editing an existing [CharacterProfile].
class CharacterEditDialog extends StatefulWidget {
  final CharacterProfile character;
  final CharacterRepository repository;

  const CharacterEditDialog({
    super.key,
    required this.character,
    required this.repository,
  });

  @override
  State<CharacterEditDialog> createState() => _CharacterEditDialogState();
}

class _CharacterEditDialogState extends State<CharacterEditDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _personalityCtrl;
  late TextEditingController _firstMsgCtrl;
  late TextEditingController _settingCtrl;
  late TextEditingController _userPersonaCtrl;
  late TextEditingController _systemPromptCtrl;
  late TextEditingController _postHistoryCtrl;
  late TextEditingController _alternateGreetingsCtrl;

  String? _selectedTemplateId;
  Uint8List? _avatarPreview;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.character.name);
    _personalityCtrl = TextEditingController(text: widget.character.personality);
    _firstMsgCtrl = TextEditingController(text: widget.character.firstMessage);
    _settingCtrl = TextEditingController(text: widget.character.setting ?? '');
    _userPersonaCtrl = TextEditingController(text: widget.character.userPersona ?? '');
    _systemPromptCtrl = TextEditingController(text: widget.character.systemPrompt ?? '');
    _postHistoryCtrl = TextEditingController(text: widget.character.postHistoryInstructions ?? '');
    _alternateGreetingsCtrl = TextEditingController(
      text: widget.character.alternateGreetings.join('\n'),
    );
    _avatarPreview = widget.character.avatarData;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _personalityCtrl.dispose();
    _firstMsgCtrl.dispose();
    _settingCtrl.dispose();
    _userPersonaCtrl.dispose();
    _systemPromptCtrl.dispose();
    _postHistoryCtrl.dispose();
    _alternateGreetingsCtrl.dispose();
    super.dispose();
  }

  void _applyTemplate(PersonaTemplate template) {
    setState(() {
      _selectedTemplateId = template.id;
      _userPersonaCtrl.text = template.description;
    });
  }

  Color _avatarColor(Uint8List? avatar, bool isDark) {
    if (avatar != null) return Colors.transparent;
    return isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant;
  }

  Future<void> _save() async {
    List<String> alternateGreetings = [];
    final greetingsText = _alternateGreetingsCtrl.text.trim();
    if (greetingsText.isNotEmpty) {
      alternateGreetings = greetingsText
          .split('\n')
          .map((g) => g.trim())
          .where((g) => g.isNotEmpty)
          .toList();
    }

    final updated = CharacterProfile(
      id: widget.character.id,
      name: _nameCtrl.text.trim().isEmpty ? widget.character.name : _nameCtrl.text.trim(),
      personality: _personalityCtrl.text.trim(),
      firstMessage: _firstMsgCtrl.text.trim(),
      setting: _settingCtrl.text.trim().isEmpty ? null : _settingCtrl.text.trim(),
      userPersona: _userPersonaCtrl.text.trim().isEmpty ? null : _userPersonaCtrl.text.trim(),
      avatarData: _avatarPreview,
      isFavorite: widget.character.isFavorite,
      systemPrompt: _systemPromptCtrl.text.trim().isEmpty ? null : _systemPromptCtrl.text.trim(),
      postHistoryInstructions: _postHistoryCtrl.text.trim().isEmpty ? null : _postHistoryCtrl.text.trim(),
      alternateGreetings: alternateGreetings,
      createdAt: widget.character.createdAt,
      updatedAt: DateTime.now(),
    );

    await widget.repository.updateCharacter(updated);
    if (mounted) {
      Navigator.of(context).pop(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final personaVM = context.watch<PersonaTemplateViewModel>();
    final displayAvatar = _avatarPreview;

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
                      if (mounted) {
                        setState(() => _avatarPreview = bytes);
                      }
                    }
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _avatarColor(displayAvatar, isDark),
                      border: Border.all(
                        color: AppTheme.accentPrimary.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: displayAvatar != null
                        ? ClipOval(
                            child: Image.memory(
                              displayAvatar,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_rounded,
                            size: 20,
                            color: AppTheme.accentPrimary,
                          ),
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
                            if (mounted) {
                              setState(() => _avatarPreview = bytes);
                            }
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
                      if (_avatarPreview != null)
                        TextButton(
                          onPressed: () => setState(() => _avatarPreview = null),
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
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _personalityCtrl,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Personality'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _firstMsgCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'First Message'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _settingCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Setting (Optional)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _alternateGreetingsCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Alternate Greetings (One per line, Optional)',
                hintText: 'One greeting per line',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _userPersonaCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Your Persona (Optional)',
                hintText: 'Describe your role in this roleplay',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedTemplateId,
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
                    if (mounted) {
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _systemPromptCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'System Prompt Override (Optional)',
                hintText: 'Use {{original}} to prepend to default prompt',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _postHistoryCtrl,
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
          onPressed: () => Navigator.of(context).pop(widget.character),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
