import 'package:flutter/material.dart';
import 'package:clan_ai/core/constants/app_theme.dart';

/// Displays alternate greetings as selectable chips below the chat input.
///
/// When a greeting is tapped, it triggers the [onSelectGreeting] callback
/// which should start a new conversation with that greeting.
class AlternateGreetingSelector extends StatelessWidget {
  final List<String> greetings;
  final VoidCallback onSelectGreeting;

  const AlternateGreetingSelector({
    super.key,
    required this.greetings,
    required this.onSelectGreeting,
  });

  @override
  Widget build(BuildContext context) {
    if (greetings.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textScaler = MediaQuery.textScalerOf(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Alternate Openings',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 44 * textScaler.scale(1),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: greetings.length,
              itemBuilder: (context, index) {
                final greeting = greetings[index];
                final displayText = greeting.length > 50
                    ? '${greeting.substring(0, 50)}...'
                    : greeting;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: onSelectGreeting,
                    borderRadius: BorderRadius.circular(20),
                    child: Chip(
                      avatar: Icon(
                        Icons.auto_awesome_rounded,
                        size: 14,
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      ),
                      label: Text(
                        displayText,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                          width: 1,
                        ),
                      ),
                      backgroundColor: isDark
                          ? AppTheme.darkSurfaceVariant.withValues(alpha: 0.5)
                          : AppTheme.lightSurfaceVariant,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
