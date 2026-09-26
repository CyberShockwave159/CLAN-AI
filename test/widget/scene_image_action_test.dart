import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/ui/features/chat/views/message_bubble.dart';
import 'package:clan_ai/ui/features/chat/views/prompt_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clan_ai/ui/shared/widgets/attachment_image.dart';

import '../helpers/test_model_factories.dart';

/// The gesture detector wrapping the rendered message image.
Finder _imageGestureTarget() {
  return find
      .ancestor(
        of: find.byType(AttachmentImage),
        matching: find.byType(GestureDetector),
      )
      .first;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('MessageBubble generate-image action', () {
    testWidgets('shows the action when a handler is supplied', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(MessageBubble(
        message: buildMessage(
          role: MessageRole.assistant,
          content: 'Alice smiles warmly.',
          status: MessageStatus.completed,
        ),
        messageIndex: 0,
        onGenerateImage: () => taps++,
      )));

      final icon = find.byIcon(Icons.auto_awesome_rounded);
      expect(icon, findsOneWidget);
      await tester.tap(icon);
      expect(taps, 1);
    });

    testWidgets('hides the action when no handler is supplied', (tester) async {
      // Assistant mode never supplies a handler, which is what keeps the
      // feature out of the assistant UI.
      await tester.pumpWidget(_wrap(MessageBubble(
        message: buildMessage(
          role: MessageRole.assistant,
          content: 'Alice smiles warmly.',
          status: MessageStatus.completed,
        ),
        messageIndex: 0,
      )));
      expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
    });

    testWidgets('hides the action on user messages', (tester) async {
      await tester.pumpWidget(_wrap(MessageBubble(
        message: buildMessage(
          role: MessageRole.user,
          content: 'hello',
          status: MessageStatus.completed,
        ),
        messageIndex: 0,
        onGenerateImage: () {},
      )));
      expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
    });

    testWidgets('hides the action while a response is streaming',
        (tester) async {
      await tester.pumpWidget(_wrap(MessageBubble(
        message: buildMessage(
          role: MessageRole.assistant,
          content: 'partial',
          status: MessageStatus.streaming,
        ),
        messageIndex: 0,
        onGenerateImage: () {},
      )));
      expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
    });

    testWidgets('long press on the image refines from that image', (tester) async {
      var generated = 0;
      var refined = 0;
      await tester.pumpWidget(_wrap(MessageBubble(
        message: buildMessage(
          role: MessageRole.assistant,
          content: 'Alice smiles warmly.',
          status: MessageStatus.completed,
          imagePath: '/tmp/does-not-exist.png',
        ),
        messageIndex: 0,
        onGenerateImage: () => generated++,
        onRefineImage: () => refined++,
      )));

      // The toolbar button and the image long-press mean opposite things:
      // restart from the character portrait vs. continue from this picture.
      await tester.tap(find.byIcon(Icons.auto_awesome_rounded));
      expect(generated, 1);
      expect(refined, 0);

      await tester.longPress(_imageGestureTarget());
      expect(refined, 1);
      expect(generated, 1, reason: 'long press must not fire the plain action');
    });

    testWidgets('long press falls back to the generate action when no refine '
        'handler is given', (tester) async {
      var generated = 0;
      await tester.pumpWidget(_wrap(MessageBubble(
        message: buildMessage(
          role: MessageRole.assistant,
          content: 'Alice smiles warmly.',
          status: MessageStatus.completed,
          imagePath: '/tmp/does-not-exist.png',
        ),
        messageIndex: 0,
        onGenerateImage: () => generated++,
      )));

      await tester.longPress(_imageGestureTarget());
      expect(generated, 1);
    });

    testWidgets('a message with no image offers no refine target',
        (tester) async {
      var refined = 0;
      await tester.pumpWidget(_wrap(MessageBubble(
        message: buildMessage(
          role: MessageRole.assistant,
          content: 'Alice smiles warmly.',
          status: MessageStatus.completed,
        ),
        messageIndex: 0,
        onGenerateImage: () {},
        onRefineImage: () => refined++,
      )));
      expect(find.byType(AttachmentImage), findsNothing);
      expect(refined, 0);
    });
  });

  group('PromptInputBar image attachment', () {
    testWidgets('shows the attach button in assistant mode', (tester) async {
      await tester.pumpWidget(_wrap(PromptInputBar(
        isGenerating: false,
        onSend: (_, _) {},
        onStop: () {},
        onOpenParams: () {},
      )));
      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
    });

    testWidgets('hides the attach button in roleplay mode', (tester) async {
      // Roleplay is text-only: an uploaded photo would enter the model's
      // context as a real conversational turn.
      await tester.pumpWidget(_wrap(PromptInputBar(
        isGenerating: false,
        isRoleplay: true,
        onSend: (_, _) {},
        onStop: () {},
        onOpenParams: () {},
      )));
      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNothing);
      expect(find.byIcon(Icons.image_rounded), findsNothing);
    });

    testWidgets('roleplay send never forwards an image path', (tester) async {
      String? sentImage;
      await tester.pumpWidget(_wrap(PromptInputBar(
        isGenerating: false,
        isRoleplay: true,
        onSend: (_, image) => sentImage = image,
        onStop: () {},
        onOpenParams: () {},
      )));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      expect(sentImage, isNull);
    });
  });
}
