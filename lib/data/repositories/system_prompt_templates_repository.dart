import 'package:clan_ai/core/utils/mutex.dart';
import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:clan_ai/data/models/system_prompt_template.dart';

class SystemPromptTemplatesRepository {
  final LocalDatabase _localDb;
  static final _mutex = Mutex();

  SystemPromptTemplatesRepository({LocalDatabase? localDb})
      : _localDb = localDb ?? LocalDatabase.instance;

  Future<List<SystemPromptTemplate>> loadTemplates() async {
    return await _localDb.loadSystemPromptTemplates();
  }

  Future<void> saveTemplates(List<SystemPromptTemplate> templates) async {
    await _localDb.saveSystemPromptTemplates(templates);
  }

  Future<SystemPromptTemplate> addTemplate(String name, String content) async {
    SystemPromptTemplate? result;
    try {
      await _mutex.run(() async {
        final templates = await loadTemplates();
        templates.add(SystemPromptTemplate(name: name, content: content));
        await saveTemplates(templates);
        result = templates.last;
      });
    } catch (_) {}
    return result ?? SystemPromptTemplate(name: name, content: content);
  }

  Future<SystemPromptTemplate> updateTemplate(int index, String name, String content) async {
    SystemPromptTemplate? result;
    try {
      await _mutex.run(() async {
        final templates = await loadTemplates();
        if (index < 0 || index >= templates.length) {
          throw RangeError.range(index, 0, templates.length - 1);
        }
        templates[index] = templates[index].copyWith(name: name, content: content);
        await saveTemplates(templates);
        result = templates[index];
      });
    } catch (_) {}
    return result ?? SystemPromptTemplate(name: name, content: content);
  }

  Future<void> deleteTemplate(int index) async {
    await _mutex.run(() async {
      final templates = await loadTemplates();
      if (index >= 0 && index < templates.length) {
        templates.removeAt(index);
        await saveTemplates(templates);
      }
    });
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
