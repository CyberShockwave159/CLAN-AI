import 'package:clan_ai/data/models/persona_template.dart';
import 'package:clan_ai/data/repositories/persona_template_repository.dart';

class FakePersonaTemplateRepository extends PersonaTemplateRepository {
  final List<PersonaTemplate> _templates = [];
  PersonaTemplate? _lastSaved;

  PersonaTemplate? get lastSaved => _lastSaved;
  List<PersonaTemplate> get all => _templates;

  @override
  Future<List<PersonaTemplate>> loadTemplates() async => _templates.toList();

  @override
  Future<void> saveTemplates(List<PersonaTemplate> templates) async {
    _templates.clear();
    _templates.addAll(templates);
  }

  @override
  Future<void> addTemplate(String name, String description) async {
    final templates = await loadTemplates();
    templates.add(PersonaTemplate(name: name, description: description));
    await saveTemplates(templates);
  }

  @override
  Future<void> updateTemplate(String id, String name, String description) async {
    final templates = await loadTemplates();
    final index = templates.indexWhere((t) => t.id == id);
    if (index != -1) {
      templates[index] = templates[index].copyWith(name: name, description: description);
      _lastSaved = templates[index];
    }
    await saveTemplates(templates);
  }

  @override
  Future<void> deleteTemplate(String id) async {
    final templates = await loadTemplates();
    templates.removeWhere((t) => t.id == id);
    await saveTemplates(templates);
  }

  @override
  Future<PersonaTemplate?> getTemplateById(String id) async {
    return _templates.where((t) => t.id == id).firstOrNull;
  }
}
