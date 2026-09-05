import 'package:flutter/material.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/data/datasources/vector_store.dart';

/// Dialog that lists all vector memories stored for a character.
///
/// Allows viewing individual memories and deleting them one by one.
class CharacterMemoriesDialog extends StatefulWidget {
  final String characterId;
  final String characterName;

  const CharacterMemoriesDialog({
    super.key,
    required this.characterId,
    required this.characterName,
  });

  @override
  State<CharacterMemoriesDialog> createState() => _CharacterMemoriesDialogState();
}

class _CharacterMemoriesDialogState extends State<CharacterMemoriesDialog> {
  final VectorStore _vectorStore = VectorStore();
  List<Map<String, dynamic>> _memories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final memories = await _vectorStore.getAllMemories(widget.characterId);
      if (mounted) {
        setState(() {
          _memories = memories;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _deleteMemory(int index) async {
    final memory = _memories[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Memory'),
        content: Text('Delete this memory?\n\n"${memory['content']}"'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.statusError),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _vectorStore.deleteEmbedding(memory['id'] as String);
        if (mounted) {
          _loadMemories();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete memory: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Text('Memories — ${widget.characterName}'),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('Error: $_error'))
                : _memories.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.memory_rounded, size: 48, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                            const SizedBox(height: 12),
                            Text(
                              'No memories stored yet',
                              style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Memories are created as conversations progress.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _memories.length,
                        itemBuilder: (ctx, index) {
                          final memory = _memories[index];
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Memory ${index + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                      color: AppTheme.statusError,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                      onPressed: () => _deleteMemory(index),
                                      tooltip: 'Delete memory',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  memory['content'] as String,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Clear All Memories?'),
                content: Text('Delete all ${_memories.length} memories for ${widget.characterName}?'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.statusError),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Clear All'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              try {
                await _vectorStore.deleteCharacterEmbeddings(widget.characterId);
                if (mounted) {
                  _loadMemories();
                  Navigator.of(context).pop(true);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to clear memories: $e')),
                  );
                }
              }
            }
          },
          style: FilledButton.styleFrom(backgroundColor: AppTheme.statusError),
          child: const Text('Clear All'),
        ),
      ],
    );
  }
}
