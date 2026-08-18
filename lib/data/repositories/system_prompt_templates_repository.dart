import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:clan_ai/data/models/system_prompt_template.dart';

class SystemPromptTemplatesRepository {
  final LocalDatabase _localDb;

  SystemPromptTemplatesRepository({LocalDatabase? localDb})
      : _localDb = localDb ?? LocalDatabase.instance;

  Future<List<SystemPromptTemplate>> loadTemplates() async {
    return await _localDb.loadSystemPromptTemplates();
  }

  Future<void> saveTemplates(List<SystemPromptTemplate> templates) async {
    await _localDb.saveSystemPromptTemplates(templates);
  }

  Future<SystemPromptTemplate> addTemplate(String name, String content) async {
    final templates = await loadTemplates();
    templates.add(SystemPromptTemplate(name: name, content: content));
    await saveTemplates(templates);
    return templates.last;
  }

  Future<SystemPromptTemplate> updateTemplate(int index, String name, String content) async {
    final templates = await loadTemplates();
    if (index >= 0 && index < templates.length) {
      templates[index] = templates[index].copyWith(name: name, content: content);
      await saveTemplates(templates);
    }
    return templates[index];
  }

  Future<void> deleteTemplate(int index) async {
    final templates = await loadTemplates();
    if (index >= 0 && index < templates.length) {
      templates.removeAt(index);
      await saveTemplates(templates);
    }
  }

  Future<SystemPromptTemplate> getTemplateByIndex(int index) async {
    final templates = await loadTemplates();
    if (index >= 0 && index < templates.length) {
      return templates[index];
    }
    throw RangeError.range(index, 0, templates.length - 1);
  }

  Future<SystemPromptTemplate?> findTemplateByName(String name) async {
    final templates = await loadTemplates();
    for (final template in templates) {
      if (template.name == name) return template;
    }
    return null;
  }
}
