import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:clan_ai/core/constants/app_theme.dart';

class PromptInputBar extends StatefulWidget {
  final bool isGenerating;
  final Function(String text) onSend;
  final VoidCallback onStop;
  final VoidCallback onOpenParams;

  const PromptInputBar({
    super.key,
    required this.isGenerating,
    required this.onSend,
    required this.onStop,
    required this.onOpenParams,
  });

  @override
  State<PromptInputBar> createState() => _PromptInputBarState();
}

class _PromptInputBarState extends State<PromptInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

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

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty && !widget.isGenerating) {
      widget.onSend(text);
      _controller.clear();
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
                child: TextField(
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
                    hintText: 'Ask anything...',
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
                        color: _hasText ? AppTheme.accentPrimary : (isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.arrow_upward_rounded,
                          color: _hasText
                              ? Colors.white
                              : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                          size: 20,
                        ),
                        onPressed: _hasText ? _handleSend : null,
                        tooltip: 'Send message',
                      ),
                    ),
            ),
          ],
        ),
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
