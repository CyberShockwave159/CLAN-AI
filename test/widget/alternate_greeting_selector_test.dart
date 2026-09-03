import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/ui/features/roleplay/widgets/alternate_greeting_selector.dart';

void main() {
  group('AlternateGreetingSelector', () {
    testWidgets('displays greeting chips', (tester) async {
      final greetings = ['Hello!', 'Hi there!', 'Greetings!'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlternateGreetingSelector(
              greetings: greetings,
              onSelectGreeting: (greeting) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Hello!'), findsOneWidget);
      expect(find.text('Hi there!'), findsOneWidget);
      expect(find.text('Greetings!'), findsOneWidget);
    });

    testWidgets('selects greeting on tap', (tester) async {
      String? selectedGreeting;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlternateGreetingSelector(
              greetings: ['Hello!', 'Hi!'],
              onSelectGreeting: (greeting) {
                selectedGreeting = greeting;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Hello!'));
      await tester.pumpAndSettle();

      expect(selectedGreeting, equals('Hello!'));
    });

    testWidgets('handles empty greetings list', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlternateGreetingSelector(
              greetings: [],
              onSelectGreeting: (greeting) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Hello!'), findsNothing);
    });

    testWidgets('handles single greeting', (tester) async {
      String? selectedGreeting;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlternateGreetingSelector(
              greetings: ['Hello!'],
              onSelectGreeting: (greeting) {
                selectedGreeting = greeting;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Hello!'));
      await tester.pumpAndSettle();

      expect(selectedGreeting, equals('Hello!'));
    });

    testWidgets('renders chip with correct label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlternateGreetingSelector(
              greetings: ['Custom Greeting'],
              onSelectGreeting: (greeting) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Custom Greeting'), findsOneWidget);
    });

    testWidgets('selects different greeting', (tester) async {
      String? selectedGreeting;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlternateGreetingSelector(
              greetings: ['First', 'Second', 'Third'],
              onSelectGreeting: (greeting) {
                selectedGreeting = greeting;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Second'));
      await tester.pumpAndSettle();

      expect(selectedGreeting, equals('Second'));
    });

    testWidgets('chip is tappable', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlternateGreetingSelector(
              greetings: ['Tap me'],
              onSelectGreeting: (greeting) {
                tapped = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final chipFinder = find.byType(Chip);
      expect(chipFinder, findsOneWidget);

      await tester.tap(chipFinder);
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('displays greeting chip in input bar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlternateGreetingSelector(
              greetings: ['Alt greeting'],
              onSelectGreeting: (greeting) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final chipFinder = find.byType(Chip);
      expect(chipFinder, findsOneWidget);
    });
  });
}
