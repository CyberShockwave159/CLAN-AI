import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
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
  late TextEditingController _nameController;
  late TextEditingController _personaController;
  bool _canSave = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existingTemplate?.name ?? '');
    _personaController = TextEditingController(text: widget.existingTemplate?.description ?? '');
    _validateFields();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _personaController.dispose();
    super.dispose();
  }

  void _validateFields() {
    setState(() {
      _canSave = _nameController.text.trim().isNotEmpty &&
          _personaController.text.trim().isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Template Name',
                        hintText: 'e.g. Soldier, Detective, Merchant',
                        prefixIcon: Icon(Icons.label_outline_rounded),
                      ),
                      onChanged: (_) => _validateFields(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _personaController,
                      maxLines: 12,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        hintText: 'Describe the user\'s role, identity, and background in this roleplay...\n\n'
                            'e.g. A seasoned bounty hunter with a cybernetic arm, seeking redemption for past crimes.',
                        prefixIcon: const Icon(Icons.description_rounded),
                        helperText: 'This will be used as the character\'s view of you during roleplay.',
                      ),
                      onChanged: (_) => _validateFields(),
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
                          backgroundColor: isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant,
                        ),
                        child: const Text('Delete'),
                      ),
                    ),
                  FilledButton(
                    onPressed: _canSave ? () {
                      if (isEditing) {
                        viewModel.updateTemplate(
                          widget.existingTemplate!.id,
                          _nameController.text.trim(),
                          _personaController.text.trim(),
                        );
                      } else {
                        viewModel.addTemplate(
                          _nameController.text.trim(),
                          _personaController.text.trim(),
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
