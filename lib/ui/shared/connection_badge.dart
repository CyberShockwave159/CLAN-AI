import 'package:flutter/material.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';

class ConnectionBadge extends StatelessWidget {
  final ServerHealthStatus status;
  final int latencyMs;
  final VoidCallback? onTap;

  const ConnectionBadge({
    super.key,
    required this.status,
    required this.latencyMs,
    this.onTap,
  });

  Color _getStatusColor() {
    switch (status) {
      case ServerHealthStatus.connected:
        return AppTheme.statusSuccess;
      case ServerHealthStatus.connecting:
        return AppTheme.statusWarning;
      case ServerHealthStatus.degraded:
        return AppTheme.accentSecondary;
      case ServerHealthStatus.offline:
        return AppTheme.statusError;
    }
  }

  String _getStatusText() {
    switch (status) {
      case ServerHealthStatus.connected:
        return latencyMs >= 0 ? '$latencyMs ms' : 'Online';
      case ServerHealthStatus.connecting:
        return 'Connecting...';
      case ServerHealthStatus.degraded:
        return 'Slow';
      case ServerHealthStatus.offline:
        return 'Offline';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    final text = _getStatusText();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
