import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:clan_ai/data/models/persona_template.dart';

class PersonaTemplateRepository {
  final LocalDatabase _localDb;

  PersonaTemplateRepository({LocalDatabase? localDb})
      : _localDb = localDb ?? LocalDatabase.instance;

  Future<List<PersonaTemplate>> loadTemplates() async {
    return await _localDb.loadPersonaTemplates();
  }

  Future<void> saveTemplates(List<PersonaTemplate> templates) async {
    await _localDb.savePersonaTemplates(templates);
  }

  Future<void> addTemplate(String name, String description) async {
    final templates = await loadTemplates();
    final newTemplate = PersonaTemplate(
      name: name,
      description: description,
    );
    templates.add(newTemplate);
    await saveTemplates(templates);
  }

  Future<void> updateTemplate(String id, String name, String description) async {
    final templates = await loadTemplates();
    final index = templates.indexWhere((t) => t.id == id);
    if (index != -1) {
      templates[index] = templates[index].copyWith(
        name: name,
        description: description,
      );
      await saveTemplates(templates);
    }
  }

  Future<void> deleteTemplate(String id) async {
    final templates = await loadTemplates();
    templates.removeWhere((t) => t.id == id);
    await saveTemplates(templates);
  }

  Future<PersonaTemplate?> getTemplateById(String id) async {
    final templates = await loadTemplates();
    for (final t in templates) {
      if (t.id == id) return t;
    }
    return null;
  }
}
