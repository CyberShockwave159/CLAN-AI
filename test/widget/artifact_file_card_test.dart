import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clan_ai/ui/features/chat/widgets/artifact_file_card.dart';

void main() {
  group('ArtifactFileCard', () {
    testWidgets('renders a generic text-document object for .txt files', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArtifactFileCard(
              fileName: 'notes.txt',
              fileMime: 'text/plain',
            ),
          ),
        ),
      );

      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.byIcon(Icons.article_outlined), findsOneWidget);
      expect(find.textContaining('Tap to save'), findsOneWidget);
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    });

    testWidgets('maps file extensions to distinct document icons', (tester) async {
      for (final entry in {
        'data.json': Icons.data_object_rounded,
        'table.csv': Icons.table_chart_outlined,
        'paper.pdf': Icons.picture_as_pdf_outlined,
        'main.py': Icons.code_rounded,
        'archive.zip': Icons.folder_zip_outlined,
        'song.mp3': Icons.audio_file_outlined,
        'video.mp4': Icons.video_file_outlined,
      }.entries) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ArtifactFileCard(fileName: entry.key),
            ),
          ),
        );
        expect(
          find.byIcon(entry.value),
          findsOneWidget,
          reason: 'expected the ${entry.key} icon to render',
        );
      }
    });

    testWidgets('tapping the whole card fires onOpen', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArtifactFileCard(
              fileName: 'report.txt',
              onOpen: () => opened++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ArtifactFileCard));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('does not fire onOpen while busy', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArtifactFileCard(
              fileName: 'a.txt',
              busy: true,
              onOpen: () => opened++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ArtifactFileCard));
      await tester.pump();
      expect(opened, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    test('mimeGuessForFileName maps common extensions', () {
      expect(FileArtifactStyle.mimeGuessForFileName('a.txt'), 'text/plain');
      expect(FileArtifactStyle.mimeGuessForFileName('a.json'), 'application/json');
      expect(FileArtifactStyle.mimeGuessForFileName('a.pdf'), 'application/pdf');
      expect(FileArtifactStyle.mimeGuessForFileName('a.csv'), 'text/csv');
      expect(FileArtifactStyle.mimeGuessForFileName('noextension'), isNull);
    });
  });
}