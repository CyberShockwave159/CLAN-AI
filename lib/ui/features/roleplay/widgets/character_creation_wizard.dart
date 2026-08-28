import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/repositories/character_repository.dart';

/// Multi-step wizard for creating a new character.
///
/// Step 1: Name, personality, first message, optional avatar
/// Step 2: Setting / world scenario (optional)
/// Step 3: User persona (optional)
class CharacterCreationWizard extends StatefulWidget {
  const CharacterCreationWizard({super.key});

  @override
  State<CharacterCreationWizard> createState() => _CharacterCreationWizardState();
}

class _CharacterCreationWizardState extends State<CharacterCreationWizard> {
  int _currentStep = 0;
  late TextEditingController _nameController;
  late TextEditingController _personalityController;
  late TextEditingController _firstMessageController;
  late TextEditingController _settingController;
  late TextEditingController _userPersonaController;
  Uint8List? _avatarData;
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _personalityController = TextEditingController();
    _firstMessageController = TextEditingController();
    _settingController = TextEditingController();
    _userPersonaController = TextEditingController();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() => _avatarData = bytes);
    }
  }

  void _saveCharacter() {
    if (_nameController.text.trim().isEmpty ||
        _personalityController.text.trim().isEmpty ||
        _firstMessageController.text.trim().isEmpty) {
      return;
    }

    final character = CharacterProfile(
      name: _nameController.text.trim(),
      personality: _personalityController.text.trim(),
      firstMessage: _firstMessageController.text.trim(),
      setting: _settingController.text.trim().isEmpty ? null : _settingController.text.trim(),
      userPersona: _userPersonaController.text.trim().isEmpty ? null : _userPersonaController.text.trim(),
      avatarData: _avatarData,
    );

    context.read<CharacterRepository>().createCharacter(character);
    Navigator.of(context).pop(character);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _personalityController.dispose();
    _firstMessageController.dispose();
    _settingController.dispose();
    _userPersonaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    'New Character',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    'Step ${_currentStep + 1} of 3',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ),
                ],
              ),
            ),

            // Progress dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) => _buildDot(i)),
            ),

            const SizedBox(height: 8),
            const Divider(height: 1),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_currentStep == 0) ..._buildStep1(isDark),
                    if (_currentStep == 1) ..._buildStep2(isDark),
                    if (_currentStep == 2) ..._buildStep3(isDark),
                  ],
                ),
              ),
            ),

            // Footer buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  Row(
                    children: [
                      if (_currentStep > 0)
                        TextButton(
                          onPressed: () => setState(() => _currentStep--),
                          child: const Text('Back'),
                        ),
                      if (_currentStep < 2)
                        FilledButton(
                          onPressed: () {
                            if (_currentStep == 0 &&
                                (_nameController.text.trim().isEmpty ||
                                    _personalityController.text.trim().isEmpty ||
                                    _firstMessageController.text.trim().isEmpty)) {
                              return;
                            }
                            setState(() => _currentStep++);
                          },
                          child: const Text('Next'),
                        ),
                      if (_currentStep == 2)
                        FilledButton(
                          onPressed: () {
                            if (_nameController.text.trim().isEmpty ||
                                _personalityController.text.trim().isEmpty ||
                                _firstMessageController.text.trim().isEmpty) {
                              return;
                            }
                            _saveCharacter();
                          },
                          child: const Text('Create'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(int index) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: index <= _currentStep
            ? AppTheme.accentPrimary
            : (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
    );
  }

  List<Widget> _buildStep1(bool isDark) => [
        // Avatar section
        Row(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _avatarData != null ? Colors.transparent : (isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant),
                  border: Border.all(
                    color: AppTheme.accentPrimary.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: _avatarData != null
                    ? ClipOval(
                        child: Image.memory(_avatarData!, width: 64, height: 64, fit: BoxFit.cover),
                      )
                    : const Icon(Icons.camera_alt_rounded, size: 24, color: AppTheme.accentPrimary),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.image_rounded, size: 16),
              label: const Text('Upload Image'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant,
                foregroundColor: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Character Name *',
            hintText: 'e.g. Aria, Shadow, Detective Blackwood',
            prefixIcon: Icon(Icons.person_rounded),
          ),
          autofocus: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _personalityController,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Personality *',
            hintText: 'Describe the character\'s personality, mannerisms, speech patterns...',
            prefixIcon: Icon(Icons.psychology_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _firstMessageController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'First Message *',
            hintText: 'The character\'s opening line when you start a conversation...',
            prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
          ),
        ),
      ];

  List<Widget> _buildStep2(bool isDark) => [
        TextField(
          controller: _settingController,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: 'Setting / World Scenario',
            hintText: 'Describe the world, environment, or scenario this roleplay takes place in...\n\n'
                'e.g. A cyberpunk city in 2157, a medieval fantasy kingdom, a post-apocalyptic wasteland...',
            prefixIcon: const Icon(Icons.map_rounded),
            helperText: 'Optional',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'The setting helps frame the character\'s responses and adds immersion. It will be included in the system prompt.',
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          ),
        ),
      ];

  List<Widget> _buildStep3(bool isDark) => [
        TextField(
          controller: _userPersonaController,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Your Persona',
            hintText: 'Describe your character\'s role in this roleplay...\n\n'
                'e.g. A wandering mercenary, a fellow detective, the character\'s closest friend...',
            prefixIcon: const Icon(Icons.account_circle_rounded),
            helperText: 'Optional',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your persona helps the character respond to you appropriately. Leave blank to play as yourself.',
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          ),
        ),
      ];
}
