import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/core/constants/aprox_capabilities.dart';
import 'package:clan_ai/core/constants/clan_theme_colors.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/models/persona_template.dart';
import 'package:clan_ai/data/repositories/character_repository.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/ui/features/roleplay/services/character_image_assist.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/persona_template_view_model.dart';
import 'package:clan_ai/ui/features/roleplay/widgets/persona_template_dialog.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';

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
  late TextEditingController _personaNameCtrl;
  late TextEditingController _personaDescriptionCtrl;
  late TextEditingController _systemPromptCtrl;
  late TextEditingController _postHistoryCtrl;
  late TextEditingController _alternateGreetingsCtrl;
  late TextEditingController _appearanceCtrl;

  String? _selectedTemplateId;
  Uint8List? _avatarPreview;
  late VisualTheme _visualTheme;

  /// Set while the "detect from avatar" request is in flight.
  bool _detectingStyle = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.character.name);
    _personalityCtrl = TextEditingController(text: widget.character.personality);
    _firstMsgCtrl = TextEditingController(text: widget.character.firstMessage);
    _settingCtrl = TextEditingController(text: widget.character.setting ?? '');
    _personaNameCtrl = TextEditingController(text: widget.character.personaName ?? 'User');
    _personaDescriptionCtrl = TextEditingController(text: widget.character.personaDescription ?? '');
    _systemPromptCtrl = TextEditingController(text: widget.character.systemPrompt ?? '');
    _postHistoryCtrl = TextEditingController(text: widget.character.postHistoryInstructions ?? '');
    _alternateGreetingsCtrl = TextEditingController(
      text: widget.character.alternateGreetings.join('\n'),
    );
    _avatarPreview = widget.character.avatarData;
    _appearanceCtrl = TextEditingController(
      text: widget.character.appearance ?? '',
    );
    _visualTheme = widget.character.visualTheme;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _personalityCtrl.dispose();
    _firstMsgCtrl.dispose();
    _settingCtrl.dispose();
    _personaNameCtrl.dispose();
    _personaDescriptionCtrl.dispose();
    _systemPromptCtrl.dispose();
    _postHistoryCtrl.dispose();
    _alternateGreetingsCtrl.dispose();
    _appearanceCtrl.dispose();
    super.dispose();
  }

  void _applyTemplate(PersonaTemplate template) {
    setState(() {
      _selectedTemplateId = template.id;
      _personaNameCtrl.text = template.personaName.isNotEmpty ? template.personaName : 'User';
      _personaDescriptionCtrl.text = template.description;
    });
  }

  Color _avatarColor(Uint8List? avatar) {
    if (avatar != null) return Colors.transparent;
    return context.clanSurfaceVariant;
  }

  /// Asks the model which visual style the current avatar is, and preselects it.
  ///
  /// A single cheap vision call, run only on request, and the result is
  /// *preselected* rather than saved — the user stays in charge of the choice,
  /// which matters because a wrong style is the thing that quietly breaks
  /// consistency.
  Future<void> _detectStyleFromAvatar() async {
    final avatar = _avatarPreview;
    if (avatar == null) return;
    setState(() => _detectingStyle = true);
    try {
      final detected = await CharacterImageAssist.detectVisualStyle(
        chatRepository: context.read<ChatRepository>(),
        serverConfig: context.read<SettingsViewModel>().config,
        connection: context.read<SettingsViewModel>().connectionDetails,
        avatarBytes: avatar,
      );
      if (!mounted) return;
      if (detected == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not detect a style. Pick one manually.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      setState(() => _visualTheme = detected);
    } finally {
      if (mounted) setState(() => _detectingStyle = false);
    }
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
      userPersona: _personaDescriptionCtrl.text.trim().isEmpty ? null : _personaDescriptionCtrl.text.trim(),
      personaName: _personaNameCtrl.text.trim().isEmpty ? 'User' : _personaNameCtrl.text.trim(),
      personaDescription: _personaDescriptionCtrl.text.trim(),
      avatarData: _avatarPreview,
      isFavorite: widget.character.isFavorite,
      systemPrompt: _systemPromptCtrl.text.trim().isEmpty ? null : _systemPromptCtrl.text.trim(),
      postHistoryInstructions: _postHistoryCtrl.text.trim().isEmpty ? null : _postHistoryCtrl.text.trim(),
      alternateGreetings: alternateGreetings,
      appearance: _appearanceCtrl.text.trim().isEmpty
          ? null
          : _appearanceCtrl.text.trim(),
      identityPortraitData: widget.character.identityPortraitData,
      visualTheme: _visualTheme,
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
                      color: _avatarColor(displayAvatar),
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
                          backgroundColor: context.clanSurfaceVariant,
                          foregroundColor: context.clanTextPrimary,
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
            const SizedBox(height: 16),
            // --- Image consistency -----------------------------------------
            // The avatar doubles as the identity reference for generated scene
            // images, so these two fields sit directly under it rather than in
            // a separate settings screen: the connection between them is the
            // whole point.
            Text(
              'Generated Images',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.clanTextSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _appearanceCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Appearance',
                hintText: 'Stable physical traits: hair, eyes, build, face',
                helperText: 'Keeps this character recognisable across generated '
                    'scenes. Clothing and setting are left out on purpose — they '
                    'change with the scene.',
                helperMaxLines: 3,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<VisualTheme>(
                    initialValue: _visualTheme,
                    decoration: InputDecoration(
                      labelText: 'Visual Style',
                      prefixIcon: const Icon(Icons.palette_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: VisualTheme.values
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t.label),
                            ))
                        .toList(),
                    onChanged: (t) => setState(() => _visualTheme = t ?? VisualTheme.none),
                  ),
                ),
                if (_avatarPreview != null) ...[
                  const SizedBox(width: 8),
                  _detectingStyle
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : TextButton(
                          onPressed: _detectStyleFromAvatar,
                          child: const Text('Detect', style: TextStyle(fontSize: 12)),
                        ),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Applied to every generated image. Match it to your avatar — a '
                'mismatch makes the reference fight the style and the character '
                'comes out inconsistent.',
                style: TextStyle(fontSize: 11, color: context.clanTextMuted),
              ),
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
              controller: _personaNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Persona Name',
                hintText: 'Name used when the character refers to you',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _personaDescriptionCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Persona Description',
                hintText: 'Brief description of your character for the AI',
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
