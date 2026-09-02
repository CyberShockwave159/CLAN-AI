import 'package:flutter_test/flutter_test.dart';
import 'package:clan_ai/core/utils/text_sanitizer.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

void main() {
  group('TextSanitizer & LaTeX/Code parsing tests', () {
    test('Splits markdown, code blocks, and LaTeX math equations accurately', () {
      const input = '''
Here is some text with inline math \$E=mc^2\$ and a block equation:
\$\$
\\int_{0}^{\\infty} e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}
\$\$
And here is a code snippet:
```python
def solve():
    return 42
```
Final conclusion.
''';

      final segments = TextSanitizer.parseSegments(input);

      expect(segments.length, equals(7));
      expect(segments[0].type, equals(SegmentType.markdown));
      expect(segments[1].type, equals(SegmentType.inlineMath));
      expect(segments[1].content, equals('E=mc^2'));
      expect(segments[2].type, equals(SegmentType.markdown));
      expect(segments[3].type, equals(SegmentType.blockMath));
      expect(segments[3].content, contains('\\int_{0}^{\\infty}'));
      expect(segments[4].type, equals(SegmentType.markdown));
      expect(segments[5].type, equals(SegmentType.codeBlock));
      expect(segments[5].content, contains('def solve():'));
      expect(segments[6].type, equals(SegmentType.markdown));
    });
  });

  group('GenerationParams serialization tests', () {
    test('Serializes OpenAI payload correctly', () {
      const params = GenerationParams(
        temperature: 0.8,
        topP: 0.95,
        maxTokens: 1024,
      );

      final payload = params.toOpenAiPayload(
        messages: [
          {'role': 'user', 'content': 'Hello'}
        ],
        model: 'llama-3.2-3b',
      );

      expect(payload['temperature'], equals(0.8));
      expect(payload['top_p'], equals(0.95));
      expect(payload['max_tokens'], equals(1024));
      expect(payload['model'], equals('llama-3.2-3b'));
      expect(payload['stream'], isTrue);
    });

    test('Serializes llama.cpp native payload correctly', () {
      const params = GenerationParams(
        temperature: 0.5,
        topK: 50,
        repeatPenalty: 1.15,
        contextSize: 8192,
      );

      final payload = params.toLlamaNativePayload(prompt: '### User:\nHi\n### Assistant:\n');

      expect(payload['temperature'], equals(0.5));
      expect(payload['top_k'], equals(50));
      expect(payload['repeat_penalty'], equals(1.15));
      expect(payload['n_ctx'], equals(8192));
      expect(payload['prompt'], contains('### User:\nHi'));
    });

    test('Includes reasoning flags when reasoning is enabled', () {
      const params = GenerationParams(
        reasoning: true,
      );

      final openAiPayload = params.toOpenAiPayload(
        messages: [
          {'role': 'user', 'content': 'Hi'}
        ],
        model: 'deepseek-r1',
      );

      expect(openAiPayload['reasoning'], isTrue);
      expect(openAiPayload['include_reasoning'], isTrue);

      final nativePayload = params.toLlamaNativePayload(prompt: 'Hi');
      expect(nativePayload['reasoning'], isTrue);
    });
  });
}
