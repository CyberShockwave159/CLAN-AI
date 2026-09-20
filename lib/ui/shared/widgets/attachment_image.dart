import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:clan_ai/core/utils/message_attachment_store.dart';

/// Renders a message image attachment referenced by [ref].
///
/// On native platforms the ref is an absolute file path, so the image is
/// decoded straight from disk via [Image.file]. On web there is no filesystem:
/// the bytes are loaded from the attachment backend (WASM sqlite) and decoded
/// via [Image.memory]. [errorBuilder] shapes the placeholder shown when the
/// bytes are missing or the image fails to decode.
///
/// The web byte-future is cached in state keyed by [ref], so parent rebuilds
/// (streaming content updates, etc.) don't re-issue a database read per frame.
class AttachmentImage extends StatefulWidget {
  const AttachmentImage({
    super.key,
    required this.ref,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  final String ref;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext context, Object error, StackTrace? stackTrace)?
      errorBuilder;

  @override
  State<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<AttachmentImage> {
  Future<Uint8List?>? _bytesFuture;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _bytesFuture = MessageAttachmentStore.instance.readBytes(widget.ref);
    }
  }

  @override
  void didUpdateWidget(covariant AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (kIsWeb && oldWidget.ref != widget.ref) {
      _bytesFuture = MessageAttachmentStore.instance.readBytes(widget.ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return FutureBuilder<Uint8List?>(
        future: _bytesFuture,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return widget.errorBuilder
                    ?.call(context, 'attachment not found', null) ??
                const SizedBox.shrink();
          }
          return Image.memory(
            bytes,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            errorBuilder: widget.errorBuilder,
          );
        },
      );
    }
    return Image.file(
      File(widget.ref),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: widget.errorBuilder,
    );
  }
}