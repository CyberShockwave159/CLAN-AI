import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/ui/features/chat/view_models/chat_view_model.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
import 'package:clan_ai/ui/features/settings/views/settings_screen.dart';
import 'package:clan_ai/ui/shared/connection_badge.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatVM = context.watch<ChatViewModel>();
    final settingsVM = context.watch<SettingsViewModel>();

    final conversationTitle = chatVM.activeThread?.title ?? 'CLAN AI';

    return AppBar(
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu_rounded, size: 22),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
          tooltip: 'Conversations',
        ),
      ),
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          conversationTitle,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
          ),
        ),
      ),
      actions: [
        // Live Health & Latency Badge
        ConnectionBadge(
          status: settingsVM.config.healthStatus,
          latencyMs: settingsVM.config.latencyMs,
          onTap: () => settingsVM.testConnection(),
        ),

        const SizedBox(width: 4),

        // Quick Settings Button
        IconButton(
          icon: const Icon(Icons.settings_outlined, size: 20),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
          tooltip: 'Settings',
        ),

        const SizedBox(width: 4),
      ],
    );
  }
}
