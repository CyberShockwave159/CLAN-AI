import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/core/utils/message_attachment_store.dart';
import 'package:clan_ai/ui/shared/snackbar_helper.dart';
import 'package:clan_ai/ui/shared/widgets/attachment_image.dart';

class PromptInputBar extends StatefulWidget {
  final bool isGenerating;
  final Function(String text, String? imagePath) onSend;
  final VoidCallback onStop;
  final VoidCallback onOpenParams;
  final bool isRoleplay;
  final String? personaName;

  const PromptInputBar({
    super.key,
    required this.isGenerating,
    required this.onSend,
    required this.onStop,
    required this.onOpenParams,
    this.isRoleplay = false,
    this.personaName,
  });

  @override
  State<PromptInputBar> createState() => _PromptInputBarState();
}

class _PromptInputBarState extends State<PromptInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  bool _hasText = false;
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasNow = _controller.text.trim().isNotEmpty;
      if (hasNow != _hasText) {
        setState(() => _hasText = hasNow);
      }
    });
  }

  Future<void> _pickImage() async {
    if (widget.isGenerating) return;

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        // Bound dimensions/quality so base64 payloads stay reasonable on
        // large phone camera images.
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;

      final bytes = await image.readAsBytes();
      final fileId = '${DateTime.now().millisecondsSinceEpoch}_${image.name
          .split('.')
          .first}';
      // On web `XFile.path` is empty — the filename is only available via
      // `name`; native keeps the absolute path (with its extension).
      final sourceName = kIsWeb ? image.name : image.path;
      final savedPath = await MessageAttachmentStore.instance.saveImage(
        fileId: fileId,
        data: bytes,
        extension: MessageAttachmentStore.extensionOf(sourceName),
      );

      // Remove a previously selected (unsent) image to avoid orphans.
      if (_imagePath != null) {
        await MessageAttachmentStore.instance.deleteIfExists(_imagePath);
      }

      if (mounted) {
        setState(() => _imagePath = savedPath);
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'Failed to attach image', duration: const Duration(seconds: 2));
      }
    }
  }

  Future<void> _removeImage() async {
    if (_imagePath == null) return;
    final path = _imagePath;
    setState(() => _imagePath = null);
    await MessageAttachmentStore.instance.deleteIfExists(path);
  }

  void _handleSend() {
    final text = _controller.text.trim();
    final imagePath = _imagePath;
    if ((text.isNotEmpty || imagePath != null) && !widget.isGenerating) {
      widget.onSend(text, imagePath);
      _controller.clear();
      // The message now owns the file — keep it on disk, just clear the
      // pending selection.
      setState(() => _imagePath = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        border: Border(
          top: BorderSide(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            width: 0.8,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Parameter Tuning Shortcut Button
            IconButton(
              icon: const Icon(Icons.tune_rounded, size: 22),
              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              onPressed: widget.onOpenParams,
              tooltip: 'Model Parameters',
            ),

            const SizedBox(width: 4),

            // Image Attach Button
            IconButton(
              icon: Icon(
                _imagePath != null
                    ? Icons.image_rounded
                    : Icons.add_photo_alternate_outlined,
                size: 22,
              ),
              color: _imagePath != null
                  ? AppTheme.accentPrimary
                  : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
              onPressed: widget.isGenerating ? null : _pickImage,
              tooltip: 'Attach image',
            ),

            const SizedBox(width: 4),

            // Input Text Field
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: _focusNode.hasFocus
                        ? AppTheme.accentPrimary
                        : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_imagePath != null) _buildImagePreview(isDark),
                    TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: 5,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.isRoleplay
                            ? 'Reply as ${widget.personaName ?? 'you'}...'
                            : 'Ask anything...',
                        hintStyle: TextStyle(
                          fontSize: 14.5,
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        fillColor: Colors.transparent,
                        filled: true,
                      ),
                      onSubmitted: (_) {
                        if (HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.shiftLeft) ||
                            HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.shiftRight)) {
                          // Shift+Enter creates a new line
                        } else {
                          _handleSend();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Send / Stop Toggle Action Button
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: widget.isGenerating
                  ? Container(
                      key: const ValueKey('stop_btn'),
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: AppTheme.statusError,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.stop_rounded, color: Colors.white, size: 22),
                        onPressed: widget.onStop,
                        tooltip: 'Stop generation',
                      ),
                    )
                  : Container(
                      key: const ValueKey('send_btn'),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _hasText || _imagePath != null
                            ? AppTheme.accentPrimary
                            : (isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.arrow_upward_rounded,
                          color: (_hasText || _imagePath != null)
                              ? Colors.white
                              : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                          size: 20,
                        ),
                        onPressed: (_hasText || _imagePath != null) ? _handleSend : null,
                        tooltip: 'Send message',
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Preview of the pending image attachment with a remove (X) overlay.
  Widget _buildImagePreview(bool isDark) {
    final imagePath = _imagePath!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AttachmentImage(
              ref: imagePath,
              height: 110,
              width: 110,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 110,
                width: 110,
                color: isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ),
            ),
          ),
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              onTap: _removeImage,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                  ),
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}