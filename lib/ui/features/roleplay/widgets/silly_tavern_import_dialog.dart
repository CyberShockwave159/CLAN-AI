import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/core/utils/st_avatar_downloader.dart';
import 'package:clan_ai/core/utils/silly_tavern_card_parser.dart';
import 'package:clan_ai/data/models/character_profile.dart';

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
    _validateFields();
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
    return CharacterProfile(
      name: _nameController.text.trim(),
      personality: _personalityController.text.trim(),
      firstMessage: _firstMessageController.text.trim(),
      setting: _settingController.text.trim().isEmpty ? null : _settingController.text.trim(),
      userPersona: _userPersonaController.text.trim().isEmpty ? null : _userPersonaController.text.trim(),
      avatarData: _avatarBytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
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

                    // User persona
                    TextField(
                      controller: _userPersonaController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Your Persona',
                        prefixIcon: const Icon(Icons.account_circle_rounded),
                        helperText: 'Optional',
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
