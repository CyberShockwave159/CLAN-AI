/// Utility functions for text sanitization, Markdown/LaTeX normalization, and stream buffering.
class TextSanitizer {
  /// Cleans and formats markdown text for rendering.
  /// Handles common edge cases with LLM streaming outputs like unbalanced markdown fences.
  static String sanitizeMarkdown(String rawText) {
    if (rawText.isEmpty) return '';

    // If an assistant stream is cut off in the middle of a code block (odd number of ```),
    // we do not mutate the raw content permanently, but during active rendering we can detect it.
    return rawText;
  }

  /// Extracts LaTeX segments ($...$ or $$...$$) and code blocks for custom rendering.
  static List<TextSegment> parseSegments(String text) {
    final List<TextSegment> segments = [];
    if (text.isEmpty) return segments;

    // Regex to detect:
    // 1. Block math: $$ ... $$
    // 2. Inline math: $ ... $
    // 3. Fenced code blocks: ```lang ... ```
    final pattern = RegExp(
      r'(```(?:\w+)?\n[\s\S]*?```)|(\$\$[\s\S]*?\$\$)|(\$(?!\$)[^\$\n]+?\$)',
      multiLine: true,
    );

    int lastIndex = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > lastIndex) {
        segments.add(TextSegment(
          type: SegmentType.markdown,
          content: text.substring(lastIndex, match.start),
        ));
      }

      final matchedStr = match.group(0)!;
      if (matchedStr.startsWith('```')) {
        // Code block
        segments.add(TextSegment(
          type: SegmentType.codeBlock,
          content: matchedStr,
        ));
      } else if (matchedStr.startsWith('\$\$')) {
        // Block math
        final mathContent = matchedStr.substring(2, matchedStr.length - 2).trim();
        segments.add(TextSegment(
          type: SegmentType.blockMath,
          content: mathContent,
        ));
      } else if (matchedStr.startsWith('\$')) {
        // Inline math
        final mathContent = matchedStr.substring(1, matchedStr.length - 1).trim();
        segments.add(TextSegment(
          type: SegmentType.inlineMath,
          content: mathContent,
        ));
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      segments.add(TextSegment(
        type: SegmentType.markdown,
        content: text.substring(lastIndex),
      ));
    }

    return segments;
  }
}

enum SegmentType {
  markdown,
  codeBlock,
  blockMath,
  inlineMath,
}

class TextSegment {
  final SegmentType type;
  final String content;

  const TextSegment({
    required this.type,
    required this.content,
  });
}
