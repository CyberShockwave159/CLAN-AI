import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/core/constants/clan_theme_colors.dart';

/// Renders an image referenced by a URL found inside an assistant message's
/// markdown natively in the chat log, mirroring how user image attachments
/// appear: a rounded, capped thumbnail that opens a zoomable fullscreen viewer
/// on tap.
///
/// Handles `http(s)` (network) and `data:` (inline bytes) schemes. If the
/// image fails to load a small in-app "Image unavailable" indicator is shown —
/// navigation is kept strictly within CLAN-AI (no external browser redirect).
class MarkdownImageView extends StatelessWidget {
  const MarkdownImageView({
    super.key,
    required this.uri,
    this.alt,
    this.width = 220,
    this.height = 220,
  });

  final Uri uri;
  final String? alt;
  final double width;
  final double height;

  bool get _isDataUri => uri.scheme == 'data';

  ImageProvider _imageProvider() {
    if (_isDataUri) {
      return MemoryImage(uri.data?.contentAsBytes() ?? Uint8List(0));
    }
    return NetworkImage(uri.toString());
  }

  Widget _fullscreenImage(BuildContext context) {
    return Image(
      image: _imageProvider(),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48),
            SizedBox(height: 8),
            Text(
              'Image unavailable',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens a fullscreen, zoomable view of the URL image.
  void _showFullscreen(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InteractiveViewer(
            maxScale: 6,
            child: Center(child: _fullscreenImage(ctx)),
          ),
        ),
      ),
    );
  }

  Widget _loadingPlaceholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.accentPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    );
  }

  Widget _errorFallback(BuildContext context, Object error, StackTrace? stackTrace) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.clanSurfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 18, color: context.clanTextMuted),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width - 60),
            child: Text(
              'Image unavailable',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: context.clanTextPrimary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () => _showFullscreen(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image(
            image: _imageProvider(),
            width: width,
            height: height,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : _loadingPlaceholder(context),
            errorBuilder: _errorFallback,
          ),
        ),
      ),
    );
  }
}