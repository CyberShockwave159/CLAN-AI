import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/data/models/app_mode.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/ui/features/chat/view_models/chat_view_model.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/roleplay_view_model.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
import 'package:clan_ai/ui/features/settings/views/settings_screen.dart';

/// Desktop keyboard shortcuts widget.
///
/// Handles Ctrl+N/Cmd+N (New Chat), Ctrl+K/Cmd+K (Search),
/// Ctrl+, (Settings), and Escape (Stop generation).
class DesktopKeyboardShortcuts extends StatefulWidget {
  final Widget child;

  const DesktopKeyboardShortcuts({required this.child, super.key});

  @override
  State<DesktopKeyboardShortcuts> createState() => _DesktopKeyboardShortcutsState();
}

class _DesktopKeyboardShortcutsState extends State<DesktopKeyboardShortcuts> {
  void _handleNewChat() {
    final settingsVM = context.read<SettingsViewModel>();
    final appMode = settingsVM.appMode;

    if (appMode == AppMode.roleplay) {
      final roleplayVM = context.read<RoleplayViewModel>();
      if (roleplayVM.activeCharacter != null) {
        roleplayVM.startRoleplay(
          roleplayVM.activeCharacter!,
          serverConfig: settingsVM.config,
          connection: settingsVM.connectionDetails,
          modelContextLength: settingsVM.getSelectedModelContextLength(),
        );
      }
    } else {
      final chatVM = context.read<ChatViewModel>();
      chatVM.createNewThread(systemPrompt: settingsVM.config.systemPrompt);
    }
  }

  void _handleSearch() {
    final chatVM = context.read<ChatViewModel>();
    if (chatVM.threads.isEmpty) return;

    showSearch<ChatThread>(
      context: context,
      delegate: _ThreadSearchDelegate(chatVM),
    );
  }

  void _handleSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _handleShortcutsHelp() {
    showDialog(
      context: context,
      builder: (_) => const ShortcutsHelpDialog(),
    );
  }

  void _handleStopGeneration() {
    final settingsVM = context.read<SettingsViewModel>();
    final appMode = settingsVM.appMode;

    if (appMode == AppMode.roleplay) {
      context.read<RoleplayViewModel>().stopGeneration();
    } else {
      context.read<ChatViewModel>().stopGeneration();
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _handleStopGeneration();
            return;
          }

          final isMod = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
          if (!isMod) return;

          switch (event.logicalKey) {
            case LogicalKeyboardKey.keyN:
              _handleNewChat();
              break;
            case LogicalKeyboardKey.keyK:
              _handleSearch();
              break;
            case LogicalKeyboardKey.comma:
              _handleSettings();
              break;
            case LogicalKeyboardKey.slash:
              if (isMod) {
                _handleShortcutsHelp();
              }
              break;
            case LogicalKeyboardKey.f1:
              _handleShortcutsHelp();
              break;
            default:
              break;
          }
        }
      },
      child: widget.child,
    );
  }
}

class ShortcutsHelpDialog extends StatelessWidget {
  const ShortcutsHelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final modLabel = isMac ? 'Cmd' : 'Ctrl';

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.keyboard, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Keyboard Shortcuts',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildShortcutRow(modLabel, 'N', 'New Chat'),
            _buildShortcutRow(modLabel, 'K', 'Search Threads'),
            _buildShortcutRow(modLabel, ',', 'Open Settings'),
            _buildShortcutRow(modLabel, '/', 'Keyboard Shortcuts Help'),
            _buildShortcutRow('', 'F1', 'Keyboard Shortcuts Help'),
            _buildShortcutRow('', 'Escape', 'Stop Generation'),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutRow(String mod, String key, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            child: Text(description, style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 16),
          Wrap(
            spacing: 4,
            children: [
              if (mod.isNotEmpty)
                _buildKey(mod),
              _buildKey(key),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKey(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      ),
    );
  }
}

class _ThreadSearchDelegate extends SearchDelegate<ChatThread> {
  final ChatViewModel chatVM;

  _ThreadSearchDelegate(this.chatVM);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear_rounded),
        onPressed: () {
          query = '';
        },
      ),
      const SizedBox(width: 8),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, chatVM.threads.isNotEmpty ? chatVM.threads.first : chatVM.threads.first),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    final q = query.toLowerCase().trim();
    final isSearching = q.isNotEmpty;

    if (isSearching) {
      return FutureBuilder<List<ChatThread>>(
        future: chatVM.searchThreads(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final results = snapshot.data!;
          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final thread = results[index];
              return ListTile(
                leading: const Icon(Icons.chat_rounded),
                title: Text(thread.title),
                subtitle: Text(
                  'Last updated: ${_formatDate(thread.updatedAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[600]
                        : Colors.grey[600],
                  ),
                ),
                onTap: () => close(context, thread),
              );
            },
          );
        },
      );
    }

    return ListView.builder(
      itemCount: chatVM.threads.length,
      itemBuilder: (context, index) {
        final thread = chatVM.threads[index];
        return ListTile(
          leading: const Icon(Icons.chat_rounded),
          title: Text(thread.title),
          subtitle: Text(
            'Last updated: ${_formatDate(thread.updatedAt)}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[600]
                  : Colors.grey[600],
            ),
          ),
          onTap: () => close(context, thread),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays == 0) {
      return 'Today at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}
