import 'package:flutter/material.dart';
import 'package:clan_ai/core/constants/clan_theme_colors.dart';

/// Shows the A-PROX `/flags` help dialog, explaining the tool-call system that
/// lets the model request image/file artifacts in the stream.
void showAproxHelpDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.info_outline_rounded, size: 40),
      title: const Text('A-PROX Artifacts'),
      content: SingleChildScrollView(
        child: Text(
          'The A-PROX server exposes a /flags tool-call system: when enabled, '
          'the model can call tools by name and request artifacts in the '
          'stream. Examples:\n\n'
          '• /image — calls the image generation tool; the generated image is '
          'delivered as an image_url artifact and appears inline in the chat.\n'
          '• /file — calls the file generation tool; the generated file is '
          'delivered as a file_url artifact and appears as a save-able document '
          'at the end of the reply.\n'
          '• /time — calls the time check tool; the result is written back into '
          'the reply text.\n\n'
          'Call /flags in your prompt to let the model generate images or files '
          'as part of its reply.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: context.clanTextPrimary,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}