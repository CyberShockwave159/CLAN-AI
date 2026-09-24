import 'package:clan_ai/core/utils/message_attachment_store.dart';

/// Utility functions for text sanitization, Markdown/LaTeX normalization, and stream buffering.
class TextSanitizer {
  /// Matches a URL whose path ends with a common raster-image extension.
  static final RegExp _imageUrlPattern = RegExp(
    r'\.(png|jpe?g|gif|webp|bmp|avif)(?:[?#][^\s]*)?$',
    caseSensitive: false,
  );

  /// Matches a `data:` URL whose MIME is a common raster-image type (used for
  /// A-PROX `inline_data_url` artifacts that are embedded as base64 payloads
  /// instead of served over HTTP).
  static final RegExp _dataImageUrlPattern = RegExp(
    r'^data:image/(?:png|jpe?g|gif|webp|bmp|avif)(?:;|,)',
    caseSensitive: false,
  );

  /// File extensions treated as LLM-generated artifacts. URLs ending in one of
  /// these are lifted out of the rendered markdown into a distinct tappable
  /// "save file" object. Ordinary web pages (no extension, `.html`, ...) and
  /// image files (rendered inline) are intentionally excluded.
  static final Set<String> artifactExtensions = <String>{
    'txt',
    'md',
    'markdown',
    'log',
    'tex',
    'json',
    'xml',
    'yaml',
    'yml',
    'toml',
    'sql',
    'csv',
    'tsv',
    'xlsx',
    'xls',
    'doc',
    'docx',
    'pptx',
    'pdf',
    'ipynb',
    'r',
    'js',
    'ts',
    'jsx',
    'tsx',
    'dart',
    'py',
    'java',
    'c',
    'h',
    'cpp',
    'cc',
    'hpp',
    'go',
    'rs',
    'rb',
    'php',
    'sh',
    'bat',
    'ps1',
    'swift',
    'kt',
    'cs',
    'css',
    'svg',
    'zip',
    'tar',
    'gz',
    '7z',
    'rar',
    'bz2',
    'mp3',
    'wav',
    'm4a',
    'ogg',
    'flac',
    'opus',
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
  };

  /// Cleans and formats markdown text for rendering.
  /// Handles common edge cases with LLM streaming outputs like unbalanced markdown fences.
  static String sanitizeMarkdown(String rawText) {
    if (rawText.isEmpty) return '';
    return rawText;
  }

  /// Returns `true` if [url] (after trailing sentence punctuation has been
  /// dropped) points at an image file.
  static bool _isImageFileUrl(String url) {
    final trimmed = url.replaceFirst(RegExp(r'[,.;:!?]+$'), '');
    return _imageUrlPattern.hasMatch(trimmed);
  }

  /// Returns `true` if [url] is a `data:` URL declaring a raster image MIME
  /// type (e.g. `data:image/png;base64,…`).
  static bool _isDataImageUrl(String url) {
    final trimmed = url.replaceFirst(RegExp(r'[,.;:!?]+$'), '');
    return _dataImageUrlPattern.hasMatch(trimmed);
  }

  /// Rewrites URLs that point at image files into markdown image syntax so the
  /// renderer can display them natively instead of as plain clickable links.
  ///
  /// Only `http`/`https` URLs are considered for path-extension detection; a
  /// `data:` URL is treated as an image when it declares a raster MIME type
  /// (`data:image/…`). Two shapes are handled:
  ///   1. `[label](http://host/image.png)` markdown links → `![label](url)`
  ///   2. bare `http://host/image.png` URLs         → `![url](url)`
  ///
  /// Existing markdown image syntax (`![alt](url)`) and URLs inside code blocks
  /// (callers should only feed markdown segment text) are left untouched.
  /// URLs that merely *contain* an image extension in the middle (`img.png.gz`)
  /// are left untouched as well.
  static String embedImageLinks(String text) {
    if (text.isEmpty) return text;

    // Fast path: nothing that looks like an image URL → unchanged.
    if (!text.toLowerCase().contains('data:image/') &&
        !text.contains(RegExp(r'\.(png|jpe?g|gif|webp|bmp|avif)', caseSensitive: false))) {
      return text;
    }

    // 1) [label](http://host/image.png) → ![label](http://host/image.png).
    // The preceding-char group keeps already-rendered `![...](...)` untouched.
    text = text.replaceAllMapped(
      RegExp(
        r'(^|[^!])\[([^\]]*)\]\((https?://[^\s)]+)\)',
        caseSensitive: false,
      ),
      (m) {
        final url = m[3]!;
        if (!_isImageFileUrl(url)) return m[0]!;
        return '${m[1]}![${m[2]}]($url)';
      },
    );

    // 2) bare http(s) image URL → ![url](url). Leading chars are restricted so
    // destinations already wrapped in `(...)` (markdown links/images) are not
    // matched a second time.
    text = text.replaceAllMapped(
      RegExp(r'(^|[\s>])https?://[^\s()\[\]<`]+', caseSensitive: false),
      (m) {
        final prefix = m[1] ?? '';
        final url = m[0]!.substring(prefix.length);
        final trimmed = url.replaceFirst(RegExp(r'[,.;:!?]+$'), '');
        if (!_imageUrlPattern.hasMatch(trimmed)) return m[0]!;
        return '$prefix![$trimmed]($trimmed)';
      },
    );

    // 3) [label](data:image/…) markdown links → ![label](url), mirroring rule 1
    // for A-PROX inline (base64 data-URL) artifacts.
    text = text.replaceAllMapped(
      RegExp(r'(^|[^!])\[([^\]]*)\]\((data:[^)]+)\)', caseSensitive: false),
      (m) {
        final url = m[3]!;
        if (!_isDataImageUrl(url)) return m[0]!;
        return '${m[1]}![${m[2]}]($url)';
      },
    );

    // 4) bare data:image/… URL → ![url](url).
    text = text.replaceAllMapped(
      RegExp(r'(^|[\s>])(data:image/[^\s()\[\]<`]+)', caseSensitive: false),
      (m) {
        final prefix = m[1] ?? '';
        final url = m[2]!;
        final trimmed = url.replaceFirst(RegExp(r'[,.;:!?]+$'), '');
        if (!_isDataImageUrl(trimmed)) return m[0]!;
        return '$prefix![$trimmed]($trimmed)';
      },
    );

    return text;
  }

  /// Finds files the model asked the user to download: markdown links and bare
  /// URLs that point at a non-image artifact file ([artifactExtensions]).
  ///
  /// Images are skipped (they render inline); URLs inside fenced code blocks
  /// and ordinary web pages stay untouched. Results are deduplicated by URL.
  /// Used to render generated files as distinct save-able objects at the end
  /// of an assistant message.
  static List<FileRef> extractFileRefs(String text) {
    if (text.isEmpty) return [];

    final refs = <FileRef>[];
    final seen = <String>{};

    void add(String url, String? label) {
      final trimmed = url.replaceFirst(RegExp(r'[,.;:!?]+$'), '');
      final ext = _fileExtensionOf(trimmed);
      if (ext == null) return;
      if (_imageUrlPattern.hasMatch(trimmed)) return;
      if (!artifactExtensions.contains(ext)) return;
      final key = trimmed.toLowerCase();
      if (!seen.add(key)) return;
      final name = MessageAttachmentStore.fileNameFromUrl(trimmed) ?? 'download.$ext';
      refs.add(FileRef(url: trimmed, fileName: name, label: label));
    }

    for (final segment in parseSegments(text)) {
      if (segment.type != SegmentType.markdown) continue;
      final content = segment.content;

      // 1) [label](http://host/file.txt)
      content.replaceAllMapped(
        RegExp(
          r'\[([^\]]*)\]\((https?://[^\s)]+)\)',
          caseSensitive: false,
        ),
        (m) {
          add(m[2]!, m[1]);
          return '';
        },
      );

      // 2) bare http(s) file URL
      content.replaceAllMapped(
        RegExp(r'(^|[\s>])https?://[^\s()\[\]<`]+', caseSensitive: false),
        (m) {
          final prefix = m[1] ?? '';
          add(m[0]!.substring(prefix.length), null);
          return '';
        },
      );
    }

    return refs;
  }

  /// Extracts the file extension (lowercase, no dot) from a URL's path, or
  /// `null` when the path has no extension. Query strings/fragments are ignored.
  static String? _fileExtensionOf(String url) {
    final path = url.split(RegExp(r'[?#]')).first.split('/').last;
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return null;
    return path.substring(dot + 1).toLowerCase();
  }

  /// Finds the first image URL in [text]: a markdown image tag
  /// (`![alt](http(s)://host/img.png)`), a markdown link to an image file
  /// (`[alt](http(s)://host/img.png)`), or a bare `http(s)://host/img.png`.
  /// A `data:` URL declaring a raster image MIME type (`data:image/…`) is
  /// treated as an image too, so A-PROX `inline_data_url` artifacts embedded
  /// in a caption are still promoted into a native attachment.
  ///
  /// Only image URLs are considered; URLs inside fenced code blocks are
  /// ignored. Returns `null` when no such URL is present. Used by the streaming
  /// layer to promote an image the model embedded in its caption text into a
  /// native bubble attachment.
  static String? extractFirstImageUrl(String text) {
    if (text.isEmpty) return null;
    if (!text.toLowerCase().contains('data:image/') &&
        !text.contains(RegExp(r'\.(png|jpe?g|gif|webp|bmp|avif)', caseSensitive: false))) {
      return null;
    }

    for (final segment in parseSegments(text)) {
      if (segment.type != SegmentType.markdown) continue;
      final content = segment.content;

      // 1) ![alt](http://host/img.png)
      for (final m in RegExp(
        r'!\[[^\]]*\]\((https?://[^\s)]+)\)',
        caseSensitive: false,
      ).allMatches(content)) {
        final url = m[1]!;
        if (_isImageFileUrl(url)) return url;
      }

      // 2) [alt](http://host/img.png). The preceding-char group keeps the
      // already-rendered `![...](...)` form from matching here.
      for (final m in RegExp(
        r'(^|[^!])\[([^\]]*)\]\((https?://[^\s)]+)\)',
        caseSensitive: false,
      ).allMatches(content)) {
        final url = m[3]!;
        if (_isImageFileUrl(url)) return url;
      }

      // 3) bare http(s) image URL
      for (final m in RegExp(
        r'(^|[\s>])https?://[^\s()\[\]<`]+',
        caseSensitive: false,
      ).allMatches(content)) {
        final prefix = m[1] ?? '';
        final url = m[0]!.substring(prefix.length).replaceFirst(
          RegExp(r'[,.;:!?]+$'),
          '',
        );
        if (_isImageFileUrl(url)) return url;
      }

      // 4) ![alt](data:image/…) markdown image tag
      for (final m in RegExp(
        r'!\[[^\]]*\]\((data:[^)]+)\)',
        caseSensitive: false,
      ).allMatches(content)) {
        final url = m[1]!;
        if (_isDataImageUrl(url)) return url;
      }

      // 5) [alt](data:image/…) markdown link
      for (final m in RegExp(
        r'(^|[^!])\[([^\]]*)\]\((data:[^)]+)\)',
        caseSensitive: false,
      ).allMatches(content)) {
        final url = m[3]!;
        if (_isDataImageUrl(url)) return url;
      }

      // 6) bare data:image/… URL
      for (final m in RegExp(
        r'(^|[\s>])(data:image/[^\s()\[\]<`]+)',
        caseSensitive: false,
      ).allMatches(content)) {
        final url = m[2]!.replaceFirst(
          RegExp(r'[,.;:!?]+$'),
          '',
        );
        if (_isDataImageUrl(url)) return url;
      }
    }

    return null;
  }

  /// Removes [imageUrl] and the markdown framing that wrapped it from [text]:
  /// `![alt](url)` / `[alt](url)` image syntax and bare `url` occurrences.
  ///
  /// Used to hide a promoted image URL from the rendered caption so the user
  /// doesn't see both a native attachment card and the raw markdown link below
  /// it. [text] is returned unchanged when the URL is absent.
  static String stripImageUrl(String text, String imageUrl) {
    if (text.isEmpty || imageUrl.isEmpty) return text;
    final url = imageUrl.replaceFirst(RegExp(r'[,.;:!?]+$'), '');
    if (url.isEmpty) return text;
    final escaped = RegExp.escape(url);
    // Drop `![..](url)` / `[..](url)` framing first...
    var result = text
        .replaceAll(RegExp(r'!\[[^\]]*\]\(' + escaped + r'\)'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]\(' + escaped + r'\)'), '');
    // ...then any bare or leftover occurrence, consuming immediately-following
    // sentence punctuation so `see http://host/img.png.` becomes `see `.
    return result.replaceAll(RegExp(escaped + r',?[.;:!?]*'), '');
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
            // Keep the opening fence + language line in the block content: the
            // renderer extracts the language from it, and the first line of
            // code must render inside the code block, not in its header.
            codeBuffer.write('$backtick$backtick$backtick');
            i += 3;
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
            // Flush markdown buffer before inline math
            if (markdownBuffer.isNotEmpty) {
              segments.add(TextSegment(type: SegmentType.markdown, content: markdownBuffer.toString()));
              markdownBuffer.clear();
            }
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

/// A file an assistant message asks the user to download: the [url] plus the
/// [fileName] derived from it and the optional markdown link [label].
class FileRef {
  final String url;
  final String fileName;
  final String? label;

  const FileRef({
    required this.url,
    required this.fileName,
    this.label,
  });
}
