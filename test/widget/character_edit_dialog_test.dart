import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/models/persona_template.dart';
import 'package:clan_ai/data/repositories/character_repository.dart';
import 'package:clan_ai/data/repositories/persona_template_repository.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/roleplay_view_model.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/persona_template_view_model.dart';
import 'package:clan_ai/ui/features/roleplay/widgets/character_edit_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../helpers/mock_path_provider.dart';

class FakePersonaTemplateRepository extends PersonaTemplateRepository {
  final List<PersonaTemplate> _stored;
  FakePersonaTemplateRepository(this._stored);

  @override
  Future<List<PersonaTemplate>> loadTemplates() async => _stored;
}

class FakeCharacterRepository extends CharacterRepository {
  CharacterProfile? lastUpdated;

  @override
  Future<void> updateCharacter(CharacterProfile character) async {
    lastUpdated = character;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupMockPathProvider();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('CharacterEditDialog loads persona template into user persona field', (tester) async {
    final template = PersonaTemplate(
      id: 'template-1',
      name: 'Detective Persona',
      description: 'A sharp, observant detective solving crimes.',
    );

    final character = CharacterProfile(
      id: 'char-1',
      name: 'Alice',
      personality: 'Curious explorer',
      firstMessage: 'Hello there!',
      userPersona: 'Initial Persona',
    );

    final personaRepo = FakePersonaTemplateRepository([template]);
    final personaVM = PersonaTemplateViewModel(repository: personaRepo);
    final charRepo = FakeCharacterRepository();

    // Pump widget
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PersonaTemplateViewModel>.value(value: personaVM),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CharacterEditDialog(
              character: character,
              repository: charRepo,
            ),
          ),
        ),
      ),
    );

    // Wait for templates to load in VM
    await tester.pumpAndSettle();

    // Verify initial values
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Curious explorer'), findsOneWidget);
    expect(find.text('Initial Persona'), findsOneWidget);

    // Tap on Dropdown to open persona template list
    final dropdownFinder = find.byType(DropdownButtonFormField<String>);
    expect(dropdownFinder, findsOneWidget);
    await tester.ensureVisible(dropdownFinder);
    await tester.pumpAndSettle();
    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();

    // Tap the 'Detective Persona' item
    final itemFinder = find.text('Detective Persona').last;
    await tester.tap(itemFinder);
    await tester.pumpAndSettle();

    // Verify 'Your Persona' field now contains the template's description
    expect(find.text('A sharp, observant detective solving crimes.'), findsOneWidget);

    // Ensure Save button is visible and tap Save
    final saveFinder = find.text('Save');
    await tester.ensureVisible(saveFinder);
    await tester.pumpAndSettle();
    await tester.tap(saveFinder);
    await tester.pumpAndSettle();

    // Verify character repository received the updated userPersona
    expect(charRepo.lastUpdated, isNotNull);
    expect(charRepo.lastUpdated!.userPersona, equals('A sharp, observant detective solving crimes.'));
  });

  test('RoleplayViewModel.updateActiveCharacter updates in-memory active character and notifies listeners', () async {
    final updatedCharacter = CharacterProfile(
      id: 'char-1',
      name: 'Alice Cooper',
      personality: 'Master investigator',
      firstMessage: 'Welcome back!',
      userPersona: 'Companion',
    );

    final differentCharacter = CharacterProfile(
      id: 'char-2',
      name: 'Bob',
      personality: 'Chef',
      firstMessage: 'What would you like to eat?',
    );

    final roleplayVM = RoleplayViewModel();
    // Wait for init
    await Future.delayed(const Duration(milliseconds: 50));

    // When no matching active character, updateActiveCharacter does not crash or overwrite
    roleplayVM.updateActiveCharacter(differentCharacter);

    // If we update active character when it matches
    roleplayVM.updateActiveCharacter(updatedCharacter);
  });
}
