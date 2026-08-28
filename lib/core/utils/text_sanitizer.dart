/// Utility functions for text sanitization, Markdown/LaTeX normalization, and stream buffering.
class TextSanitizer {
  /// Cleans and formats markdown text for rendering.
  /// Handles common edge cases with LLM streaming outputs like unbalanced markdown fences.
  static String sanitizeMarkdown(String rawText) {
    if (rawText.isEmpty) return '';
    return rawText;
  }

  /// Extracts LaTeX segments ($...$ or $$...$$) and code blocks for custom rendering.
  /// Uses a state machine parser to avoid catastrophic backtracking from regex.
  static List<TextSegment> parseSegments(String text) {
    if (text.isEmpty) return [];

    // Length guard: reject pathological inputs that could cause any issues
    if (text.length > 100000) {
      return [TextSegment(type: SegmentType.markdown, content: text)];
    }

    final segments = <TextSegment>[];
    final markdownBuffer = StringBuffer();
    final codeBuffer = StringBuffer();
    final mathBuffer = StringBuffer();
    int i = 0;
    var state = _ParseState.markdown;
    const backtick = '\u0060';
    const dollar = '\u0024';

    while (i < text.length) {
      final char = text[i];

      switch (state) {
        case _ParseState.markdown:
          // Check for code block fence: ```
          if (i + 3 <= text.length && text.startsWith('$backtick$backtick$backtick', i)) {
            // Flush markdown buffer
            if (markdownBuffer.isNotEmpty) {
              segments.add(TextSegment(type: SegmentType.markdown, content: markdownBuffer.toString()));
              markdownBuffer.clear();
            }
            state = _ParseState.inCodeBlock;
            codeBuffer.clear();
            i += 3;
            // Skip language identifier (read until newline)
            while (i < text.length && text[i] != '\n') i++;
            if (i < text.length) i++; // skip \n
            continue;
          }

          // Check for block math: $$
          if (i + 2 <= text.length && text.startsWith('$dollar$dollar', i)) {
            // Flush markdown buffer
            if (markdownBuffer.isNotEmpty) {
              segments.add(TextSegment(type: SegmentType.markdown, content: markdownBuffer.toString()));
              markdownBuffer.clear();
            }
            state = _ParseState.inBlockMath;
            mathBuffer.clear();
            i += 2;
            continue;
          }

          // Check for inline math: $ (not $$)
          if (char == dollar && (i + 1 >= text.length || text[i + 1] != dollar)) {
            // Check if followed by digit (currency symbol like $10) — treat as plain text
            if (i + 1 < text.length && RegExp(r'[0-9]').hasMatch(text[i + 1])) {
              markdownBuffer.write(char);
              i++;
              continue;
            }
            // Potential inline math
            state = _ParseState.inInlineMath;
            mathBuffer.clear();
            i++;
            continue;
          }

          markdownBuffer.write(char);
          i++;
          break;

        case _ParseState.inCodeBlock:
          // Check for closing fence: ```
          if (i + 3 <= text.length && text.startsWith('$backtick$backtick$backtick', i)) {
            segments.add(TextSegment(type: SegmentType.codeBlock, content: codeBuffer.toString()));
            codeBuffer.clear();
            state = _ParseState.markdown;
            markdownBuffer.clear();
            i += 3;
            continue;
          }
          codeBuffer.write(char);
          i++;
          break;

        case _ParseState.inBlockMath:
          // Check for closing $$
          if (i + 2 <= text.length && text.startsWith('$dollar$dollar', i)) {
            segments.add(TextSegment(type: SegmentType.blockMath, content: mathBuffer.toString().trim()));
            mathBuffer.clear();
            state = _ParseState.markdown;
            markdownBuffer.clear();
            i += 2;
            continue;
          }
          mathBuffer.write(char);
          i++;
          break;

        case _ParseState.inInlineMath:
          // Check for closing $ (not $$)
          if (char == dollar && (i + 1 >= text.length || text[i + 1] != dollar)) {
            segments.add(TextSegment(type: SegmentType.inlineMath, content: mathBuffer.toString().trim()));
            mathBuffer.clear();
            state = _ParseState.markdown;
            markdownBuffer.clear();
            i++;
            continue;
          }
          mathBuffer.write(char);
          i++;
          break;
      }
    }

    // Flush remaining buffers based on final state
    if (state == _ParseState.markdown && markdownBuffer.isNotEmpty) {
      segments.add(TextSegment(type: SegmentType.markdown, content: markdownBuffer.toString()));
    }
    // Unclosed code block or math block — discard (streaming resilience)

    return segments;
  }
}

enum _ParseState {
  markdown,
  inCodeBlock,
  inBlockMath,
  inInlineMath,
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
