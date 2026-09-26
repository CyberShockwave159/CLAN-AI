import 'package:flutter/material.dart';

/// Opens a fullscreen, zoomable view of an image, with an explicit close button.
///
/// Call it instead of hand-rolling a `showDialog` + `Dialog` + `InteractiveViewer`
/// stack; two call sites had drifted into near-duplicates of each other.
///
/// [image] is the already-built image widget (an [Image] for a URL, an
/// [AttachmentImage] for a stored attachment, …). It is only laid out, never
/// re-fetched, so the caller keeps ownership of caching and error states.
class FullscreenImageViewer extends StatelessWidget {
  const FullscreenImageViewer({super.key, required this.image});

  /// The zoomable content, sized by the dialog.
  final Widget image;

  /// Presents [image] over the current route.
  static Future<void> show(BuildContext context, Widget image) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => FullscreenImageViewer(image: image),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black87,
      insetPadding: const EdgeInsets.all(16),
      // A `Dialog` is only as dismissible as the barrier the user can actually
      // hit. On a phone the inset shrinks to a few points once a portrait image
      // is scaled to fit, so "tap outside to close" stops being a usable
      // affordance and the view looks like a dead end. The close button is the
      // reliable way out; the barrier stays as a convenience.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 6,
              child: Center(child: image),
            ),
            // Outside the InteractiveViewer on purpose: inside it, the pan and
            // pinch recognizers share the gesture arena with the tap, so a drag
            // that started on the button could leave the button un-pressed.
            const Positioned(top: 4, right: 4, child: _CloseButton()),
          ],
        ),
      ),
    );
  }
}

/// A transparent close affordance pinned to the top-right of the viewer.
///
/// The glyph is white on the viewer's black scrim, with a soft shadow rather
/// than a filled background: a transparent button is what was asked for, but a
/// bare white X disappears against a light photograph, and a solid chip would
/// sit on top of the image the user opened. The shadow keeps the glyph legible
/// over both without occluding anything.
class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close image',
      child: Tooltip(
        message: 'Close',
        child: InkResponse(
          // 44x44 is Apple's minimum comfortable tap target; the glyph stays
          // 22 so the visible mark is unobtrusive.
          radius: 24,
          onTap: () => Navigator.of(context).maybePop(),
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.close,
              size: 22,
              color: Colors.white,
              shadows: [
                Shadow(color: Colors.black87, blurRadius: 6),
                Shadow(color: Colors.black54, blurRadius: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
