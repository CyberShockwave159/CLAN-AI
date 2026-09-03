import 'package:flutter/material.dart';

/// Shared handler for message deletion with undo support.
///
/// Extracted from ChatScreen and RoleplayScreen to eliminate duplicate
/// delete/undo/snackbar logic while keeping each screen's specific
/// delete/undo methods intact.
Future<void> handleDeleteMessage({
  required BuildContext context,
  required Future<bool> Function() deleteFn,
  required bool canUndo,
  required Future<void> Function() undoFn,
  required void Function() onThreadDeleted,
}) async {
  final shouldDeleteThread = await deleteFn();
  if (shouldDeleteThread) {
    onThreadDeleted();
  } else if (canUndo) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Message deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: undoFn,
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
