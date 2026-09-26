import 'package:clan_ai/core/constants/clan_theme_colors.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/ui/shared/widgets/attachment_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Offers to generate a character's reference portrait before their first scene
/// image.
///
/// Without a reference, A-PROX falls back to text-to-image and the character
/// comes back looking like a different person every time — the single biggest
/// thing that breaks immersion. Offering the portrait once, here, is the moment
/// where that is cheap to fix.
///
/// Returns `true` when the caller should proceed with the scene image.
Future<bool?> showPortraitOfferDialog({
  required BuildContext context,
  required CharacterProfile character,
  required Future<String?> Function() onGeneratePortrait,
  /// Drafts a canonical appearance description from the character card, for
  /// review before it is stored. Null disables the offer.
  Future<String?> Function()? onDraftAppearance,
  /// Persists an approved appearance description.
  Future<void> Function(String appearance)? onSaveAppearance,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _PortraitOfferDialog(
      character: character,
      onGeneratePortrait: onGeneratePortrait,
      onDraftAppearance: onDraftAppearance,
      onSaveAppearance: onSaveAppearance,
    ),
  );
}

class _PortraitOfferDialog extends StatefulWidget {
  final CharacterProfile character;
  final Future<String?> Function() onGeneratePortrait;
  final Future<String?> Function()? onDraftAppearance;
  final Future<void> Function(String appearance)? onSaveAppearance;

  const _PortraitOfferDialog({
    required this.character,
    required this.onGeneratePortrait,
    this.onDraftAppearance,
    this.onSaveAppearance,
  });

  @override
  State<_PortraitOfferDialog> createState() => _PortraitOfferDialogState();
}

class _PortraitOfferDialogState extends State<_PortraitOfferDialog> {
  bool _generating = false;
  bool _failed = false;
  String? _previewPath;

  /// Non-null while the appearance review sheet is open.
  String? _appearanceDraft;
  final TextEditingController _appearanceCtrl = TextEditingController();

  @override
  void dispose() {
    _appearanceCtrl.dispose();
    super.dispose();
  }

  /// Opens the appearance review sheet, seeded with a fresh draft.
  ///
  /// The draft is never stored without the user seeing it: a wrong appearance
  /// sheet is invisible until the images come out wrong, and it is pinned into
  /// every future generation.
  Future<void> _draftAppearance() async {
    final draft = await widget.onDraftAppearance?.call();
    if (!mounted) return;
    if (draft == null || draft.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No physical details found in the card.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    setState(() {
      _appearanceDraft = draft;
      _appearanceCtrl.text = draft;
    });
  }

  Future<void> _saveAppearance() async {
    final text = _appearanceCtrl.text.trim();
    if (text.isEmpty) return;
    await widget.onSaveAppearance?.call(text);
    if (!mounted) return;
    setState(() {
      _appearanceDraft = null;
      _appearanceCtrl.clear();
    });
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _failed = false;
    });
    try {
      final path = await widget.onGeneratePortrait();
      if (!mounted) return;
      setState(() {
        _previewPath = path;
        _generating = false;
        _failed = path == null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPreview = _previewPath != null;
    final reviewing = _appearanceDraft != null;
    return AlertDialog(
      title: Text(reviewing
          ? "Describe ${widget.character.name}'s appearance"
          : 'Reference portrait for ${widget.character.name}?'),
      content: SizedBox(
        width: 320,
        child: reviewing ? _buildAppearanceReview(context) : _buildOffer(context),
      ),
      actions: reviewing ? _reviewActions(context) : _offerActions(context, hasPreview),
    );
  }

  /// The main offer: explain why a reference matters, preview the portrait, and
  /// offer the one-time appearance draft.
  Widget _buildOffer(BuildContext context) {
    final hasPreview = _previewPath != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasPreview
              ? 'This portrait conditions every scene image, keeping '
                  '${widget.character.name} recognizable. Approve it, or '
                  'generate another.'
              : 'Scene images condition on a reference portrait so '
                  '${widget.character.name} keeps the same face. '
                  '${widget.character.name} has no avatar yet, so one can be '
                  'generated now.',
          style: TextStyle(fontSize: 13, color: context.clanTextSecondary),
        ),
        const SizedBox(height: 14),
        if (_generating)
          const Center(child: CircularProgressIndicator())
        else if (hasPreview)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AttachmentImage(
                ref: _previewPath!,
                width: 220,
                height: 220,
                fit: BoxFit.contain,
              ),
            ),
          )
        else if (_failed)
          Text(
            'Generation failed. You can still generate the scene without a '
            'reference, but the character may look different each time.',
            style: TextStyle(fontSize: 12, color: context.clanTextMuted),
          ),
        if (widget.onDraftAppearance != null && !widget.character.hasAppearance) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _generating ? _draftAppearance : null,
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('Draft appearance from card'),
          ),
        ],
      ],
    );
  }

  List<Widget> _offerActions(BuildContext context, bool hasPreview) {
    return [
      TextButton(
        onPressed: _generating ? null : () => Navigator.of(context).pop(false),
        child: Text(hasPreview ? 'Cancel' : 'Skip'),
      ),
      if (hasPreview)
        TextButton(
          onPressed: _generating ? null : _generate,
          child: const Text('Regenerate'),
        ),
      FilledButton(
        onPressed: _generating
            ? null
            : () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop(true);
              },
        child: Text(hasPreview ? 'Use this' : 'Generate & continue'),
      ),
    ];
  }

  /// The appearance review sheet: the model's draft, editable, saved explicitly.
  Widget _buildAppearanceReview(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'These traits are pinned into every generated image so the character '
          'stays recognisable. Correct anything the model got wrong, then save.',
          style: TextStyle(fontSize: 12, color: context.clanTextSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _appearanceCtrl,
          maxLines: 6,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  List<Widget> _reviewActions(BuildContext context) {
    return [
      TextButton(
        onPressed: () => setState(() {
          _appearanceDraft = null;
          _appearanceCtrl.clear();
        }),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _saveAppearance, child: const Text('Save')),
    ];
  }
}
