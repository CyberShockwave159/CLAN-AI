import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/ui/features/settings/views/sections/app_mode_section.dart';
import 'package:clan_ai/ui/features/settings/views/sections/profile_section.dart';
import 'package:clan_ai/ui/features/settings/views/sections/safety_section.dart';
import 'package:clan_ai/data/datasources/vector_store.dart';
import 'package:clan_ai/data/models/app_mode.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/models/persona_template.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/system_prompt_template.dart';
import 'package:clan_ai/data/repositories/character_repository.dart';
import 'package:clan_ai/ui/features/chat/view_models/chat_view_model.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
import 'package:clan_ai/ui/features/settings/views/parameter_tuning_sheet.dart';
import 'package:clan_ai/ui/shared/connection_badge.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/persona_template_view_model.dart';
import 'package:clan_ai/ui/features/roleplay/widgets/persona_template_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _systemPromptController;
  bool _obscureApiKey = true;
  late SettingsViewModel _settingsVM;
  late ChatViewModel _chatVM;

  @override
  void initState() {
    super.initState();
    _settingsVM = context.read<SettingsViewModel>();
    _urlController = TextEditingController(text: _settingsVM.config.baseUrl);
    _apiKeyController = TextEditingController(text: _settingsVM.config.apiKey ?? '');

    _chatVM = context.read<ChatViewModel>();
    String initialPrompt;
    if (_chatVM.activeThread != null) {
      final threadPrompt = _chatVM.activeThread!.systemPrompt;
      initialPrompt = threadPrompt ?? _settingsVM.config.systemPrompt ?? defaultSystemPrompt;
    } else {
      initialPrompt = _settingsVM.config.systemPrompt ?? defaultSystemPrompt;
    }
    _systemPromptController = TextEditingController(text: initialPrompt);

    _settingsVM.addListener(_syncControllers);
    _chatVM.addListener(_syncControllers);
  }

  void _syncControllers() {
    if (_urlController.text != _settingsVM.config.baseUrl) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _urlController.text != _settingsVM.config.baseUrl) {
          _urlController.text = _settingsVM.config.baseUrl;
        }
      });
    }

    final apiKeyText = _settingsVM.config.apiKey ?? '';
    if (_apiKeyController.text != apiKeyText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _apiKeyController.text != apiKeyText) {
          _apiKeyController.text = apiKeyText;
        }
      });
    }

    String effectivePrompt;
    if (_chatVM.activeThread != null) {
      effectivePrompt = _chatVM.activeThread!.systemPrompt ?? _settingsVM.config.systemPrompt ?? defaultSystemPrompt;
    } else {
      effectivePrompt = _settingsVM.config.systemPrompt ?? defaultSystemPrompt;
    }
    if (_systemPromptController.text != effectivePrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _systemPromptController.text != effectivePrompt) {
          _systemPromptController.text = effectivePrompt;
        }
      });
    }
  }

  void _openParameterSheet(BuildContext context, SettingsViewModel vm) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ParameterTuningSheet(
        initialParams: vm.config.defaultParams,
        onSave: (newParams) => vm.updateDefaultParams(newParams),
      ),
    );
  }

  void _showAddTemplateDialog() {
    final nameController = TextEditingController();
    final contentController = TextEditingController();
    final settingsVM = context.read<SettingsViewModel>();

    showDialog(
      context: context,
      builder: (ctx) => WillPopScope(
        onWillPop: () async {
          nameController.dispose();
          contentController.dispose();
          return true;
        },
        child: AlertDialog(
          title: const Text('New System Prompt Template'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Template Name',
                    hintText: 'e.g. Academic Researcher',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'System Prompt',
                    hintText: 'Enter the system instructions...',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final content = contentController.text.trim();
                if (name.isEmpty || content.isEmpty) return;
                settingsVM.addTemplate(name, content);
                Navigator.of(ctx).pop();
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteTemplate(int index) {
    final settingsVM = context.read<SettingsViewModel>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Template?'),
        content: Text(
            'Are you sure you want to delete "${settingsVM.templates[index].name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.statusError),
            onPressed: () {
              settingsVM.deleteTemplate(index);
              Navigator.of(ctx).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _applyTemplateToPrompt(SystemPromptTemplate template) {
    _systemPromptController.text = template.content;
    context.read<SettingsViewModel>().updateSystemPrompt(template.content);
    final chatVM = context.read<ChatViewModel>();
    if (chatVM.activeThread != null) {
      chatVM.updateActiveThreadSystemPrompt(template.content);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settingsVM = context.watch<SettingsViewModel>();
    final chatVM = context.watch<ChatViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Settings', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ConnectionBadge(
              status: settingsVM.config.healthStatus,
              latencyMs: settingsVM.config.latencyMs,
              onTap: () => settingsVM.testConnection(),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Selector
          _buildSectionHeader('Server Profiles', Icons.storage_rounded),
          const SizedBox(height: 10),

          ProfileSection(),

          const SizedBox(height: 24),

          // Section 1: Server Connection Configuration
          _buildSectionHeader('Server Connection', Icons.dns_rounded),
          const SizedBox(height: 10),

          // Server URL Input
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'Server Base URL',
              hintText: 'http://127.0.0.1:8080 or http://192.168.1.100:8080',
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check_rounded),
                onPressed: () {
                  settingsVM.updateBaseUrl(_urlController.text.trim());
                  settingsVM.testConnection();
                },
                tooltip: 'Apply & Test',
              ),
            ),
            onSubmitted: (val) {
              settingsVM.updateBaseUrl(val.trim());
              settingsVM.testConnection();
            },
          ),

          const SizedBox(height: 12),

          // API Key Input
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            decoration: InputDecoration(
              labelText: 'API Authentication Key (Optional)',
              hintText: 'sk-llama-cpp-key...',
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscureApiKey ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
              ),
            ),
            onChanged: (val) => settingsVM.updateApiKey(val.trim().isEmpty ? null : val.trim()),
          ),

          const SizedBox(height: 12),

          // Protocol Selector
          Row(
            children: [
              Expanded(
                child: SegmentedButton<ApiProtocol>(
                  segments: const [
                    ButtonSegment(
                      value: ApiProtocol.openAi,
                      label: Text('OpenAI API'),
                      icon: Icon(Icons.api_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: ApiProtocol.llamaNative,
                      label: Text('llama.cpp Native'),
                      icon: Icon(Icons.memory_rounded, size: 16),
                    ),
                  ],
                  selected: {settingsVM.connectionDetails?.protocol ?? ApiProtocol.openAi},
                  onSelectionChanged: (selected) {
                    settingsVM.updateProtocol(selected.first);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Test Connection Button & Error Banner
          FilledButton.icon(
            icon: settingsVM.isTestingConnection
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.network_check_rounded, size: 18),
            label: Text(
              settingsVM.isTestingConnection ? 'Testing Server...' : 'Test Connection & Ping',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: settingsVM.isTestingConnection
                ? null
                : () {
                    settingsVM.updateBaseUrl(_urlController.text.trim());
                    settingsVM.testConnection();
                  },
          ),

          if (settingsVM.testConnectionError != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.statusError.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.statusError.withValues(alpha: 0.3)),
              ),
              child: Text(
                'Connection Error: ${settingsVM.testConnectionError}',
                style: const TextStyle(color: AppTheme.statusError, fontSize: 12.5),
              ),
            ),

          const SizedBox(height: 24),

          // Section 2: Model Selection & Context
          _buildSectionHeader('Model Selection', Icons.smart_toy_rounded),
          const SizedBox(height: 10),

          if (settingsVM.availableModels.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: settingsVM.config.selectedModel ?? settingsVM.availableModels.first.id,
              decoration: const InputDecoration(
                labelText: 'Active Model',
                prefixIcon: Icon(Icons.model_training_rounded),
              ),
              items: settingsVM.availableModels.map((m) {
                return DropdownMenuItem(
                  value: m.id,
                  child: Text(m.name, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  settingsVM.updateSelectedModel(val);
                }
              },
            )
          else
            Text(
              'No models fetched yet. Click "Test Connection" while the server is running to query available models.',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                fontSize: 13,
              ),
            ),

          const SizedBox(height: 24),

          if (settingsVM.appMode == AppMode.assistant) ...[
            // Section 3: System Prompt Configuration
            _buildSectionHeader('System Prompt Customization', Icons.psychology_rounded),
            const SizedBox(height: 10),

            // Active thread indicator
            if (chatVM.activeThread != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded, size: 16, color: AppTheme.accentPrimary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        chatVM.activeThread!.systemPrompt != null
                            ? 'Editing prompt for: ${chatVM.activeThread!.title}'
                            : 'Editing global default prompt',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),

            TextField(
              controller: _systemPromptController,
              maxLines: 4,
              minLines: 2,
              decoration: const InputDecoration(
                hintText: 'Enter global system instructions...',
              ),
              onChanged: (val) {
                final trimmed = val.trim();
                settingsVM.updateSystemPrompt(trimmed);

                // If active thread has a system prompt, update the thread too
                if (chatVM.activeThread != null && chatVM.activeThread!.systemPrompt != null) {
                  chatVM.updateActiveThreadSystemPrompt(trimmed);
                }
              },
            ),

            const SizedBox(height: 8),

            // Saved Templates Section
            Row(
              children: [
                Text(
                  'Saved Templates',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showAddTemplateDialog,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('New'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            if (settingsVM.templates.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'No saved templates yet. Click "New" to create one.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  ),
                ),
              )
            else
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: settingsVM.templates.length,
                  itemBuilder: (context, templateIndex) {
                    final template = settingsVM.templates[templateIndex];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => _applyTemplateToPrompt(template),
                        child: Chip(
                          avatar: Icon(Icons.psychology_rounded, size: 16, color: AppTheme.accentPrimary),
                          label: Text(template.name, style: const TextStyle(fontSize: 12)),
                          onDeleted: () => _deleteTemplate(templateIndex),
                          deleteIconColor: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: AppTheme.accentPrimary.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],

          const SizedBox(height: 24),

          // Section 4: Hyperparameters
          _buildSectionHeader('Generation Sampling Defaults', Icons.tune_rounded),
          const SizedBox(height: 10),

          OutlinedButton.icon(
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Configure Sampling Parameters (Temp, Top-P, Top-K, Context)'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _openParameterSheet(context, settingsVM),
          ),

          const SizedBox(height: 24),

          // Section 5: Safety & Convenience
          _buildSectionHeader('Safety & Convenience', Icons.security_rounded),
          const SizedBox(height: 10),

          SafetySection(),

          const SizedBox(height: 40),

          // Section 6: RAG Memory Management (roleplay only)
          if (settingsVM.appMode == AppMode.roleplay) ...[
            _buildSectionHeader('RAG Memory', Icons.auto_stories_rounded),
            const SizedBox(height: 10),

            FutureBuilder<List<CharacterProfile>>(
              future: context.read<CharacterRepository>().getAllCharacters(),
              builder: (ctx, charSnapshot) {
                if (charSnapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (!charSnapshot.hasData || charSnapshot.data!.isEmpty) {
                  return Text(
                    'No characters with memories yet.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: charSnapshot.data!.map((character) {
                    final charId = character.id;
                    final charName = character.name;
                    return FutureBuilder<int>(
                      future: VectorStore().getEmbeddingCount(charId),
                      builder: (ctx2, countSnapshot) {
                        if (countSnapshot.connectionState != ConnectionState.done) {
                          return const SizedBox.shrink();
                        }
                        final count = countSnapshot.data ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(Icons.memory_rounded, size: 16, color: AppTheme.accentPrimary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$charName: $count memory${count == 1 ? '' : 's'}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              if (count > 0)
                                TextButton(
                                  onPressed: () async {
                                    await VectorStore().deleteCharacterEmbeddings(charId);
                                    if (mounted) setState(() {});
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Cleared $count memories for $charName'),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  ),
                                  child: const Text('Clear', style: TextStyle(fontSize: 12)),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 8),

            OutlinedButton.icon(
              onPressed: () async {
                final chars = await context.read<CharacterRepository>().getAllCharacters();
                for (final char in chars) {
                  await VectorStore().deleteCharacterEmbeddings(char.id);
                }
                if (mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All memories cleared'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.clear_all_rounded, size: 16),
              label: const Text('Clear All Memories'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                side: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
              ),
            ),
          ],

          const SizedBox(height: 40),

          // Section: Persona Templates (roleplay mode only)
          if (settingsVM.appMode == AppMode.roleplay) ...[
            _buildSectionHeader('Persona Templates', Icons.person_outline_rounded),
            const SizedBox(height: 10),

  FutureBuilder<List<PersonaTemplate>>(
            future: _loadPersonaTemplates(),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final templates = snapshot.data ?? [];

              if (templates.isEmpty) {
                return Text(
                  'No persona templates yet. Click "New" to create one.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 44,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: templates.length,
                      itemBuilder: (context, templateIndex) {
                        final template = templates[templateIndex];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => _showEditPersonaTemplateDialog(template),
                            child: Chip(
                              avatar: Icon(Icons.person_outline_rounded, size: 16, color: AppTheme.accentPrimary),
                              label: Text(template.name, style: const TextStyle(fontSize: 12)),
                              onDeleted: () => _deletePersonaTemplate(template.id),
                              deleteIconColor: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: AppTheme.accentPrimary.withValues(alpha: 0.3),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 12),

          FilledButton.icon(
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New Persona Template'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _showEditPersonaTemplateDialog(null),
          ),
          ],

          const SizedBox(height: 40),

          // Section: App Mode
          _buildSectionHeader('App Mode', Icons.view_agenda_rounded),
          const SizedBox(height: 10),

          AppModeSection(),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.accentPrimary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  Future<List<PersonaTemplate>> _loadPersonaTemplates() async {
    return context.watch<PersonaTemplateViewModel>().templates;
  }

  void _showEditPersonaTemplateDialog(PersonaTemplate? template) {
    showDialog<void>(
      context: context,
      builder: (_) => PersonaTemplateDialog(existingTemplate: template),
    );
  }

  void _deletePersonaTemplate(String id) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Template?'),
        content: Text('Are you sure you want to delete this persona template?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.statusError),
            onPressed: () {
              context.read<PersonaTemplateViewModel>().deleteTemplate(id);
              Navigator.of(ctx).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _settingsVM.removeListener(_syncControllers);
    _chatVM.removeListener(_syncControllers);
    _urlController.dispose();
    _apiKeyController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }
}
