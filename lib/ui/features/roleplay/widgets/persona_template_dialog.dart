import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/clan_theme_colors.dart';
import 'package:clan_ai/data/models/persona_template.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/persona_template_view_model.dart';

/// Dialog for creating or editing a persona template.
///
/// Returns the created/updated [PersonaTemplate] on save, or null on cancel.
class PersonaTemplateDialog extends StatefulWidget {
  final PersonaTemplate? existingTemplate;

  const PersonaTemplateDialog({super.key, this.existingTemplate});

  @override
  State<PersonaTemplateDialog> createState() => _PersonaTemplateDialogState();
}

class _PersonaTemplateDialogState extends State<PersonaTemplateDialog> {
  late TextEditingController _templateNameController;
  late TextEditingController _personaNameController;
  late TextEditingController _personaDescriptionController;
  bool _canSave = false;

  @override
  void initState() {
    super.initState();
    _templateNameController = TextEditingController(text: widget.existingTemplate?.name ?? '');
    _personaNameController = TextEditingController(text: widget.existingTemplate?.personaName ?? '');
    _personaDescriptionController = TextEditingController(text: widget.existingTemplate?.description ?? '');
    _validateFields();
  }

  @override
  void dispose() {
    _templateNameController.dispose();
    _personaNameController.dispose();
    _personaDescriptionController.dispose();
    super.dispose();
  }

  void _validateFields() {
    final descText = _personaDescriptionController.text.trim();
    setState(() {
      _canSave = descText.isNotEmpty;
    });
  }

  void _onTemplateNameChanged(String value) {
    if (value.trim().isEmpty && _personaDescriptionController.text.trim().isNotEmpty) {
      final firstWord = _personaDescriptionController.text.trim().split(RegExp(r'\s+')).first;
      _personaNameController.text = firstWord;
    }
    _validateFields();
  }

  void _onPersonaDescriptionChanged(String value) {
    if (value.trim().isNotEmpty && _templateNameController.text.trim().isEmpty) {
      final firstWord = value.trim().split(RegExp(r'\s+')).first;
      _personaNameController.text = firstWord;
    }
    _validateFields();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<PersonaTemplateViewModel>();
    final isEditing = widget.existingTemplate != null;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    isEditing ? 'Edit Persona Template' : 'New Persona Template',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _templateNameController,
                      decoration: const InputDecoration(
                        labelText: 'Template Name',
                        hintText: 'e.g. Soldier, Detective, Merchant',
                        prefixIcon: Icon(Icons.label_outline_rounded),
                      ),
                      onChanged: (_) => _onTemplateNameChanged(_templateNameController.text),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _personaNameController,
                      decoration: const InputDecoration(
                        labelText: 'Persona Name',
                        hintText: 'Name used when the character refers to you',
                        prefixIcon: Icon(Icons.badge_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _personaDescriptionController,
                      maxLines: 12,
                      decoration: InputDecoration(
                        labelText: 'Persona Description',
                        hintText: 'Describe the user\'s role, identity, and background in this roleplay...\n\n'
                            'e.g. A seasoned bounty hunter with a cybernetic arm, seeking redemption for past crimes.',
                        prefixIcon: const Icon(Icons.description_rounded),
                        helperText: 'This will be used as the character\'s view of you during roleplay.',
                      ),
                      onChanged: (_) => _onPersonaDescriptionChanged(_personaDescriptionController.text),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isEditing)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: FilledButton.tonal(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Template'),
                              content: Text('Are you sure you want to delete "${widget.existingTemplate!.name}"?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton.tonal(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true && mounted) {
                            await viewModel.deleteTemplate(widget.existingTemplate!.id);
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: context.clanSurfaceVariant,
                        ),
                        child: const Text('Delete'),
                      ),
                    ),
                  FilledButton(
                    onPressed: _canSave ? () {
                      if (isEditing) {
                        viewModel.updateTemplate(
                          widget.existingTemplate!.id,
                          _templateNameController.text.trim(),
                          _personaNameController.text.trim(),
                          _personaDescriptionController.text.trim(),
                        );
                      } else {
                        final personaName = _personaNameController.text.trim().isEmpty
                            ? (_personaDescriptionController.text.trim().split(RegExp(r'\s+')).first)
                            : _personaNameController.text.trim();
                        viewModel.addTemplate(
                          _templateNameController.text.trim(),
                          personaName,
                          _personaDescriptionController.text.trim(),
                        );
                      }
                      Navigator.of(context).pop();
                    } : null,
                    child: Text(isEditing ? 'Save Changes' : 'Create Template'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
