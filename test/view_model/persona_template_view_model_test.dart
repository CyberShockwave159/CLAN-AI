import 'package:clan_ai/data/repositories/persona_template_repository.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/persona_template_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_persona_template_repository.dart';


void main() {
  late FakePersonaTemplateRepository fakeRepo;
  late PersonaTemplateViewModel vm;

  setUp(() {
    fakeRepo = FakePersonaTemplateRepository();
    vm = PersonaTemplateViewModel(repository: fakeRepo);
  });

  group('PersonaTemplateViewModel loadTemplates', () {
    test('returns loaded templates', () async {
      final templates = await fakeRepo.loadTemplates();
      expect(templates, isEmpty);
    });

    test('returns templates when they exist', () async {
      await fakeRepo.addTemplate('Template 1', 'Description 1');
      await fakeRepo.addTemplate('Template 2', 'Description 2');

      final templates = await fakeRepo.loadTemplates();
      expect(templates, hasLength(2));
    });
  });

  group('PersonaTemplateViewModel addTemplate', () {
    test('adds template', () async {
      await vm.addTemplate('Test Template', 'Test description');

      expect(vm.templates, isNotEmpty);
      expect(vm.templates.first.name, equals('Test Template'));
      expect(vm.templates.first.description, equals('Test description'));
    });

    test('template has generated id', () async {
      await vm.addTemplate('Test', 'Desc');

      expect(vm.templates.first.id, isNotNull);
    });

    test('template has timestamps', () async {
      await vm.addTemplate('Test', 'Desc');

      expect(vm.templates.first.createdAt, isNotNull);
      expect(vm.templates.first.updatedAt, isNotNull);
    });
  });

  group('PersonaTemplateViewModel updateTemplate', () {
    test('updates template', () async {
      await vm.addTemplate('Original', 'Old description');
      final template = vm.templates.first;

      await vm.updateTemplate(template.id, 'Updated', 'New description');

      expect(vm.templates.first.name, equals('Updated'));
      expect(vm.templates.first.description, equals('New description'));
    });

    test('updates updatedAt on modification', () async {
      await vm.addTemplate('Test', 'Desc');
      final template = vm.templates.first;
      final originalUpdated = template.updatedAt;

      await Future.delayed(const Duration(milliseconds: 10));
      await vm.updateTemplate(template.id, 'Test', 'Updated');

      expect(vm.templates.first.updatedAt.isAfter(originalUpdated), isTrue);
    });

    test('does not update non-existent template', () async {
      await vm.addTemplate('Keep', 'Description');

      await vm.updateTemplate('non-existent', 'Changed', 'Description');

      expect(vm.templates.first.name, equals('Keep'));
    });
  });

  group('PersonaTemplateViewModel deleteTemplate', () {
    test('deletes template', () async {
      await vm.addTemplate('Delete Me', 'Description');

      await vm.deleteTemplate(vm.templates.first.id);

      expect(vm.templates, isEmpty);
    });

    test('does nothing for non-existent template', () async {
      await vm.addTemplate('Keep', 'Description');

      await vm.deleteTemplate('non-existent');

      expect(vm.templates, hasLength(1));
    });

    test('removes only specified template', () async {
      await vm.addTemplate('Keep 1', 'Desc 1');
      await vm.addTemplate('Keep 2', 'Desc 2');
      final templateToDelete = vm.templates[1];

      await vm.deleteTemplate(templateToDelete.id);

      expect(vm.templates, hasLength(1));
      expect(vm.templates.first.name, equals('Keep 1'));
    });
  });

  group('PersonaTemplateViewModel templates getter', () {
    test('returns current templates list', () async {
      await vm.addTemplate('Template 1', 'Desc 1');
      await vm.addTemplate('Template 2', 'Desc 2');

      expect(vm.templates, hasLength(2));
    });

    test('returns empty list when no templates', () {
      expect(vm.templates, isEmpty);
    });
  });

  group('PersonaTemplateViewModel dispose', () {
    test('disposes without error', () async {
      await vm.addTemplate('Test', 'Desc');
      vm.dispose();
    });
  });
}
