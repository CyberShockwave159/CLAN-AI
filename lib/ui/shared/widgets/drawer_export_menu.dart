import 'package:flutter/material.dart';

/// Shared export menu items used by both ChatDrawer and RoleplayDrawer.
/// Returns the two PopupMenuItems for TXT and JSON export.
List<PopupMenuEntry<String>> buildExportMenuItems() {
  return [
    const PopupMenuItem(
      value: 'export_txt',
      child: Row(
        children: [
          Icon(Icons.file_copy_outlined, size: 18),
          SizedBox(width: 8),
          Text('Export as TXT'),
        ],
      ),
    ),
    const PopupMenuItem(
      value: 'export_json',
      child: Row(
        children: [
          Icon(Icons.code_outlined, size: 18),
          SizedBox(width: 8),
          Text('Export as JSON'),
        ],
      ),
    ),
  ];
}

/// Shared export success snackbar display.
/// Call after export completes to show the result.
void showExportSuccess(BuildContext context, String path) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Exported to $path'),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
