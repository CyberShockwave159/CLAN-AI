import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/ui/shared/snackbar_helper.dart';

/// Picks a conversation JSON export file and imports it via [onImport].
///
/// Shared by ChatDrawer and RoleplayDrawer, which previously duplicated this
/// flow inline. Closes the drawer, reads + validates the picked file, then
/// hands the parsed thread/messages to [onImport] before reporting success or
/// failure with the standard snackbars. Returns silently when the user
/// cancels the file picker.
Future<void> importConversationFromJsonFile(
  BuildContext context, {
  required Future<void> Function(ChatThread thread, List<ChatMessage> messages) onImport,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) return;
  final picked = result.files.first;
  // Web file pickers expose the content bytes instead of a filesystem path.
  if (picked.path == null && picked.bytes == null) return;

  if (!context.mounted) return;
  Navigator.of(context).pop();

  try {
    final content = picked.bytes != null
        ? utf8.decode(picked.bytes!)
        : await File(picked.path!).readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    if (!json.containsKey('thread') || !json.containsKey('messages')) {
      if (context.mounted) showAppSnackBar(context, 'Invalid import file format');
      return;
    }

    final (thread, messages, _) = ConversationExport.fromJson(json);

    if (!context.mounted) return;
    await onImport(thread, messages);
    if (context.mounted) showAppSnackBar(context, 'Chat imported successfully');
  } catch (e) {
    if (context.mounted) showAppSnackBar(context, 'Import failed: $e');
  }
}