import 'package:flutter/material.dart';
import 'package:clan_ai/core/constants/clan_theme_colors.dart';

/// Displays alternate greetings as selectable chips below the chat input.
///
/// When a greeting is tapped, it triggers the [onSelectGreeting] callback
/// with the selected greeting text, which should start a new conversation
/// using that specific greeting.
class AlternateGreetingSelector extends StatelessWidget {
  final List<String> greetings;
  final Function(String selectedGreeting) onSelectGreeting;

  const AlternateGreetingSelector({
    super.key,
    required this.greetings,
    required this.onSelectGreeting,
  });

  @override
  Widget build(BuildContext context) {
    if (greetings.isEmpty) return const SizedBox.shrink();

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
                color: context.clanTextMuted,
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
                    onTap: () => onSelectGreeting(greeting),
                    borderRadius: BorderRadius.circular(20),
                    child: Chip(
                      avatar: Icon(
                        Icons.auto_awesome_rounded,
                        size: 14,
                        color: context.clanTextMuted,
                      ),
                      label: Text(
                        displayText,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.clanTextPrimary,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: context.clanBorder,
                          width: 1,
                        ),
                      ),
                      backgroundColor: Theme.of(context).brightness == Brightness.dark
                          ? context.clanSurfaceVariant.withValues(alpha: 0.5)
                          : context.clanSurfaceVariant,
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
