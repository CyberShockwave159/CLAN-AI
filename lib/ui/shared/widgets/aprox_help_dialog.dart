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
          'the model can request image and file artifacts. Generated artifacts '
          'are delivered as image_url / file_url entries in the stream and '
          'appear inline in this chat.\n\n'
          'Call /flags in your prompt to let the model generate images or '
          'files as part of its reply.',
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