import 'dart:async';

import 'package:flutter/material.dart';
import 'package:clan_ai/core/constants/app_theme.dart';

/// Shows the standard destructive-confirmation dialog used across the app:
/// a red "Delete" [FilledButton] next to "Cancel".
///
/// The dialog closes itself before [onConfirm] runs, matching the behavior of
/// every previous inline delete dialog. [onConfirm] may be async; callers are
/// responsible for their own post-delete state handling (as they were before).
Future<void> showConfirmDeleteDialog(
  BuildContext context, {
  required String title,
  required Widget content,
  required FutureOr<void> Function() onConfirm,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.statusError),
          onPressed: () async {
            Navigator.of(ctx).pop();
            await onConfirm();
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}