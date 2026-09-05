import 'package:clan_ai/data/repositories/persona_template_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_character_repository.dart';
import '../helpers/fake_persona_template_repository.dart';
import '../helpers/test_model_factories.dart';

/// Tests: Persona template isolation and application.
void main() {
  late FakePersonaTemplateRepository templateRepo;
  late FakeCharacterRepository charRepo;

  setUp(() {
    templateRepo = FakePersonaTemplateRepository();
    charRepo = FakeCharacterRepository();
  });

  test('template application to character sets userPersona', () async {
    // Create template
    await templateRepo.addTemplate('Detective', 'A sharp detective persona');
    final template = templateRepo.all.first;

    // Create character with template applied
    final char = buildCharacter(
      name: 'Aria',
      id: 'char-1',
      userPersona: template.description,
    );
    await charRepo.createCharacter(char);

    expect(charRepo.all.first.userPersona, equals('A sharp detective persona'));
  });

  test('independent characters with same template are not linked', () async {
    // Create template
    await templateRepo.addTemplate('Detective', 'A sharp detective persona');
    final template = templateRepo.all.first;

    // Create two characters with same template applied
    final char1 = buildCharacter(
      name: 'Aria',
      id: 'char-1',
      userPersona: template.description,
    );
    final char2 = buildCharacter(
      name: 'Bob',
      id: 'char-2',
      userPersona: template.description,
    );
    await charRepo.createCharacter(char1);
    await charRepo.createCharacter(char2);

    // Update character 1's persona
    final updated1 = char1.copyWith(userPersona: 'Updated detective');
    await charRepo.updateCharacter(updated1);

    // Character 2 should be unaffected
    final reloaded2 = await charRepo.getCharacterById('char-2');
    expect(reloaded2!.userPersona, equals('A sharp detective persona'));
  });

  test('template update does not affect existing characters', () async {
    // Create template and character
    await templateRepo.addTemplate('Detective', 'Original description');
    final templateId = templateRepo.all.first.id;

    final char = buildCharacter(
      name: 'Aria',
      id: 'char-1',
      userPersona: 'Original description',
    );
    await charRepo.createCharacter(char);

    // Update template
    await templateRepo.updateTemplate(templateId, 'Detective', 'Updated description');

    // Character should still have old value
    final reloaded = await charRepo.getCharacterById('char-1');
    expect(reloaded!.userPersona, equals('Original description'));
  });

  test('template deletion does not affect characters', () async {
    // Create template and character
    await templateRepo.addTemplate('Detective', 'Description');
    final templateId = templateRepo.all.first.id;

    final char = buildCharacter(
      name: 'Aria',
      id: 'char-1',
      userPersona: 'Description',
    );
    await charRepo.createCharacter(char);

    // Delete template
    await templateRepo.deleteTemplate(templateId);

    // Character should still exist
    final reloaded = await charRepo.getCharacterById('char-1');
    expect(reloaded, isNotNull);
    expect(reloaded!.userPersona, equals('Description'));
  });

  test('persona template has independent lifecycle', () async {
    // Create template
    await templateRepo.addTemplate('Detective', 'Description');
    final templateId = templateRepo.all.first.id;

    // Update template
    await templateRepo.updateTemplate(templateId, 'Detective', 'Updated');

    // Delete template
    await templateRepo.deleteTemplate(templateId);

    // Template should be gone
    expect(templateRepo.all, isEmpty);
  });

  test('multiple templates can coexist', () async {
    await templateRepo.addTemplate('Template 1', 'Desc 1');
    await templateRepo.addTemplate('Template 2', 'Desc 2');
    await templateRepo.addTemplate('Template 3', 'Desc 3');

    expect(templateRepo.all, hasLength(3));

    // Delete middle template
    await templateRepo.deleteTemplate(templateRepo.all[1].id);

    expect(templateRepo.all, hasLength(2));
  });

  test('character copyWith preserves userPersona independently', () async {
    final char = buildCharacter(
      name: 'Aria',
      id: 'char-1',
      userPersona: 'Original persona',
    );
    final updated = char.copyWith(userPersona: 'New persona');

    expect(updated.userPersona, equals('New persona'));
    expect(char.userPersona, equals('Original persona'));
  });
}
