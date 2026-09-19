import 'package:flutter/material.dart';

/// Shows the app-standard floating snackbar with rounded corners.
///
/// Mirrors the inline `SnackBar` styling that was previously repeated across
/// drawers and screens (floating behavior + 10px rounded shape). Callers that
/// cross an `await` boundary must still guard with `context.mounted`
/// themselves (or rely on the surrounding async context) as before.
void showAppSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}