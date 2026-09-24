import 'package:clan_ai/core/utils/text_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextSanitizer.embedImageLinks', () {
    test('converts markdown links to image files into markdown images', () {
      expect(
        TextSanitizer.embedImageLinks('[View](https://host/img.png)'),
        '![View](https://host/img.png)',
      );
    });

    test('converts bare image URLs into markdown images', () {
      expect(
        TextSanitizer.embedImageLinks('here: https://host/gen_123.png ok'),
        'here: ![https://host/gen_123.png](https://host/gen_123.png) ok',
      );
    });

    test('supports jpg, jpeg, gif, webp, bmp, avif and uppercase extensions', () {
      expect(
        TextSanitizer.embedImageLinks('a https://h/x.JPG b https://h/y.webp'),
        'a ![https://h/x.JPG](https://h/x.JPG) b ![https://h/y.webp](https://h/y.webp)',
      );
      expect(
        TextSanitizer.embedImageLinks('https://h/a.jpeg'),
        '![https://h/a.jpeg](https://h/a.jpeg)',
      );
      expect(
        TextSanitizer.embedImageLinks('https://h/a.avif'),
        '![https://h/a.avif](https://h/a.avif)',
      );
    });

    test('keeps URLs with query strings intact', () {
      expect(
        TextSanitizer.embedImageLinks('https://h/img.png?size=200&token=abc'),
        '![https://h/img.png?size=200&token=abc](https://h/img.png?size=200&token=abc)',
      );
      expect(
        TextSanitizer.embedImageLinks('[pic](https://h/img.jpeg?w=100)'),
        '![pic](https://h/img.jpeg?w=100)',
      );
    });

    test('leaves existing markdown image syntax untouched', () {
      const input = '![alt](https://host/img.png)';
      expect(TextSanitizer.embedImageLinks(input), input);
    });

    test('leaves non-image links untouched', () {
      const input = '[OpenAI](https://openai.com) and https://openai.com';
      expect(TextSanitizer.embedImageLinks(input), input);
    });

    test('leaves URLs without image extensions untouched', () {
      const input = 'go to https://host/page or https://host/img.png.gz';
      expect(TextSanitizer.embedImageLinks(input), input);
      expect(
        TextSanitizer.embedImageLinks('download https://host/img.png.zip here'),
        'download https://host/img.png.zip here',
      );
    });

    test('strips trailing sentence punctuation from converted URLs', () {
      expect(
        TextSanitizer.embedImageLinks('see https://host/img.png for more.'),
        'see ![https://host/img.png](https://host/img.png) for more.',
      );
      expect(
        TextSanitizer.embedImageLinks('credits: https://host/a.JPG.'),
        'credits: ![https://host/a.JPG](https://host/a.JPG)',
      );
    });

    test('keeps URLs with underscores intact', () {
      expect(
        TextSanitizer.embedImageLinks('https://host/gen_1.png'),
        '![https://host/gen_1.png](https://host/gen_1.png)',
      );
    });

    test('handles empty input', () {
      expect(TextSanitizer.embedImageLinks(''), '');
      expect(TextSanitizer.embedImageLinks('  plain text  '), '  plain text  ');
    });

    test('converts multiple links and bare URLs in a paragraph', () {
      const input = '[a](http://h/1.png) and http://h/2.jpg together [b](http://h/3.gif)';
      expect(
        TextSanitizer.embedImageLinks(input),
        '![a](http://h/1.png) and ![http://h/2.jpg](http://h/2.jpg) together ![b](http://h/3.gif)',
      );
    });
  });

  group('TextSanitizer.parseSegments code blocks', () {
    test('keeps the opening fence, language, and full first line', () {
      const input = '```python\ndef solve():\n    return 42\n```';
      final segments = TextSanitizer.parseSegments(input);

      expect(segments, hasLength(1));
      expect(segments.single.type, equals(SegmentType.codeBlock));
      expect(segments.single.content, equals('```python\ndef solve():\n    return 42\n'));
    });

    test('preserves a very long first line inside the code content', () {
      const firstLine =
          'def extremely_long_function_name_without_any_spacing_that_would_previously_have_been_misread_as_the_language(a, b):';
      final segments = TextSanitizer.parseSegments('```dart\n$firstLine\n  pass\n```');

      expect(segments.single.type, equals(SegmentType.codeBlock));
      expect(segments.single.content, contains(firstLine));
    });

    test('code block without a language line still keeps its first line', () {
      final segments = TextSanitizer.parseSegments('```\nvoid main() {}\n```');

      expect(segments.single.type, equals(SegmentType.codeBlock));
      expect(segments.single.content, equals('```\nvoid main() {}\n'));
    });
  });

  group('TextSanitizer.extractFileRefs', () {
    test('extracts a markdown link to a text file', () {
      final refs = TextSanitizer.extractFileRefs('See [download](http://host/result.txt) done');

      expect(refs, hasLength(1));
      expect(refs.single.url, equals('http://host/result.txt'));
      expect(refs.single.fileName, equals('result.txt'));
      expect(refs.single.label, equals('download'));
    });

    test('extracts a bare PDF URL', () {
      final refs = TextSanitizer.extractFileRefs('Report: http://host/report.pdf');

      expect(refs, hasLength(1));
      expect(refs.single.url, equals('http://host/report.pdf'));
      expect(refs.single.fileName, equals('report.pdf'));
    });

    test('handles query strings and trailing sentence punctuation', () {
      final refs = TextSanitizer.extractFileRefs('grab http://host/data.csv?token=abc now.');

      expect(refs, hasLength(1));
      expect(refs.single.url, equals('http://host/data.csv?token=abc'));
      expect(refs.single.fileName, equals('data.csv'));
    });

    test('excludes image URLs (they render inline)', () {
      expect(
        TextSanitizer.extractFileRefs('[pic](http://host/img.png) http://host/a.jpg'),
        isEmpty,
      );
    });

    test('excludes ordinary web pages', () {
      expect(
        TextSanitizer.extractFileRefs(
          '[home](https://example.com) and https://example.com/page.html',
        ),
        isEmpty,
      );
    });

    test('excludes URLs inside fenced code blocks', () {
      const text = '```\nhttp://host/inside.txt\n```\n\nsee http://host/outside.txt';
      final refs = TextSanitizer.extractFileRefs(text);

      expect(refs, hasLength(1));
      expect(refs.single.fileName, equals('outside.txt'));
    });

    test('deduplicates repeated URLs', () {
      expect(
        TextSanitizer.extractFileRefs('http://host/a.json and [a.json](http://host/a.json)'),
        hasLength(1),
      );
    });

    test('returns nothing for empty or image-only text', () {
      expect(TextSanitizer.extractFileRefs(''), isEmpty);
      expect(TextSanitizer.extractFileRefs('just some words'), isEmpty);
    });
  });
}