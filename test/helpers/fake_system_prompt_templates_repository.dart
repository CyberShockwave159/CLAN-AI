import 'package:clan_ai/data/models/system_prompt_template.dart';
import 'package:clan_ai/data/repositories/system_prompt_templates_repository.dart';

class FakeSystemPromptTemplatesRepository extends SystemPromptTemplatesRepository {
  final List<SystemPromptTemplate> _templates = [];
  SystemPromptTemplate? _lastSaved;

  SystemPromptTemplate? get lastSaved => _lastSaved;
  List<SystemPromptTemplate> get all => _templates;

  @override
  Future<List<SystemPromptTemplate>> loadTemplates() async => _templates.toList();

  @override
  Future<void> saveTemplates(List<SystemPromptTemplate> templates) async {
    _templates.clear();
    _templates.addAll(templates);
  }

  @override
  Future<SystemPromptTemplate> addTemplate(String name, String content) async {
    final templates = await loadTemplates();
    final newTemplate = SystemPromptTemplate(name: name, content: content);
    templates.add(newTemplate);
    await saveTemplates(templates);
    return newTemplate;
  }

  @override
  Future<SystemPromptTemplate> updateTemplate(int index, String name, String content) async {
    final templates = await loadTemplates();
    if (index >= 0 && index < templates.length) {
      templates[index] = templates[index].copyWith(name: name, content: content);
      _lastSaved = templates[index];
      await saveTemplates(templates);
      return templates[index];
    }
    throw RangeError.range(index, 0, templates.length - 1);
  }

  @override
  Future<void> deleteTemplate(int index) async {
    final templates = await loadTemplates();
    if (index >= 0 && index < templates.length) {
      templates.removeAt(index);
      await saveTemplates(templates);
    }
  }

  @override
  Future<SystemPromptTemplate> getTemplateByIndex(int index) async {
    final templates = await loadTemplates();
    if (index >= 0 && index < templates.length) {
      return templates[index];
    }
    throw RangeError.range(index, 0, templates.length - 1);
  }
}
