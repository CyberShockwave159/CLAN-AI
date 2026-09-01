import 'package:flutter/foundation.dart';
import 'package:clan_ai/data/repositories/persona_template_repository.dart';
import 'package:clan_ai/data/models/persona_template.dart';

class PersonaTemplateViewModel extends ChangeNotifier {
  final PersonaTemplateRepository _repository;

  List<PersonaTemplate> _templates = [];
  List<PersonaTemplate> get templates => _templates;

  PersonaTemplateViewModel({PersonaTemplateRepository? repository})
      : _repository = repository ?? PersonaTemplateRepository() {
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    _templates = await _repository.loadTemplates();
    notifyListeners();
  }

  Future<void> addTemplate(String name, String description) async {
    await _repository.addTemplate(name, description);
    await _loadTemplates();
  }

  Future<void> updateTemplate(String id, String name, String description) async {
    await _repository.updateTemplate(id, name, description);
    await _loadTemplates();
  }

  Future<void> deleteTemplate(String id) async {
    await _repository.deleteTemplate(id);
    await _loadTemplates();
  }

  PersonaTemplate? getTemplateById(String id) {
    for (final t in _templates) {
      if (t.id == id) return t;
    }
    return null;
  }
}
