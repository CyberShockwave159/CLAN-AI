import 'package:flutter/material.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/core/constants/clan_theme_colors.dart';

/// Visual category for a generated file. Drives the "generic text document",
/// "spreadsheet", "PDF", ... icon shown on [ArtifactFileCard].
enum FileArtifactKind {
  text,
  data,
  sheet,
  markdown,
  pdf,
  code,
  archive,
  audio,
  video,
  fallback,
}

/// Icon / label / mime mapping for [FileArtifactKind].
class FileArtifactStyle {
  /// Classifies [fileName] (extension wins) or [mime] as a fallback.
  static FileArtifactKind kindFor(String? fileName, String? mime) {
    final ext = extensionOf(fileName);
    if (ext != null) return kindForExtension(ext);
    return kindForMime(mime);
  }

  static FileArtifactKind kindForExtension(String ext) {
    switch (ext) {
      case 'txt':
      case 'log':
      case 'doc':
      case 'docx':
      case 'tex':
        return FileArtifactKind.text;
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
      case 'toml':
      case 'sql':
      case 'ipynb':
      case 'r':
        return FileArtifactKind.data;
      case 'csv':
      case 'tsv':
      case 'xlsx':
      case 'xls':
        return FileArtifactKind.sheet;
      case 'md':
      case 'markdown':
        return FileArtifactKind.markdown;
      case 'pdf':
        return FileArtifactKind.pdf;
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
      case 'rar':
      case 'bz2':
        return FileArtifactKind.archive;
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'ogg':
      case 'flac':
      case 'opus':
        return FileArtifactKind.audio;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
        return FileArtifactKind.video;
      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
      case 'dart':
      case 'py':
      case 'java':
      case 'c':
      case 'h':
      case 'cpp':
      case 'cc':
      case 'hpp':
      case 'go':
      case 'rs':
      case 'rb':
      case 'php':
      case 'sh':
      case 'bat':
      case 'ps1':
      case 'swift':
      case 'kt':
      case 'cs':
      case 'css':
        return FileArtifactKind.code;
      default:
        return FileArtifactKind.fallback;
    }
  }

  static FileArtifactKind kindForMime(String? mime) {
    if (mime == null) return FileArtifactKind.fallback;
    final m = mime.toLowerCase();
    if (m.startsWith('text/')) return FileArtifactKind.text;
    if (m.contains('json') || m.contains('xml') || m.contains('yaml')) {
      return FileArtifactKind.data;
    }
    if (m.contains('csv') || m.contains('spreadsheet') || m.contains('excel')) {
      return FileArtifactKind.sheet;
    }
    if (m.contains('markdown')) return FileArtifactKind.markdown;
    if (m.contains('pdf')) return FileArtifactKind.pdf;
    if (m.contains('zip') || m.contains('compressed') || m.contains('tar')) {
      return FileArtifactKind.archive;
    }
    if (m.startsWith('audio/')) return FileArtifactKind.audio;
    if (m.startsWith('video/')) return FileArtifactKind.video;
    return FileArtifactKind.fallback;
  }

  static IconData iconFor(FileArtifactKind kind) {
    switch (kind) {
      case FileArtifactKind.text:
        return Icons.article_outlined;
      case FileArtifactKind.data:
        return Icons.data_object_rounded;
      case FileArtifactKind.sheet:
        return Icons.table_chart_outlined;
      case FileArtifactKind.markdown:
        return Icons.notes_rounded;
      case FileArtifactKind.pdf:
        return Icons.picture_as_pdf_outlined;
      case FileArtifactKind.code:
        return Icons.code_rounded;
      case FileArtifactKind.archive:
        return Icons.folder_zip_outlined;
      case FileArtifactKind.audio:
        return Icons.audio_file_outlined;
      case FileArtifactKind.video:
        return Icons.video_file_outlined;
      case FileArtifactKind.fallback:
        return Icons.insert_drive_file_outlined;
    }
  }

  static String labelFor(FileArtifactKind kind) {
    switch (kind) {
      case FileArtifactKind.text:
        return 'Text document';
      case FileArtifactKind.data:
        return 'Data file';
      case FileArtifactKind.sheet:
        return 'Spreadsheet';
      case FileArtifactKind.markdown:
        return 'Markdown document';
      case FileArtifactKind.pdf:
        return 'PDF document';
      case FileArtifactKind.code:
        return 'Code file';
      case FileArtifactKind.archive:
        return 'Archive';
      case FileArtifactKind.audio:
        return 'Audio';
      case FileArtifactKind.video:
        return 'Video';
      case FileArtifactKind.fallback:
        return 'File';
    }
  }

  /// A reasonable `mime` for [fileName] when the server didn't declare one
  /// (e.g. file URLs lifted from markdown). `null` when unknown.
  static String? mimeGuessForFileName(String? fileName) {
    switch (extensionOf(fileName)) {
      case 'txt':
      case 'log':
        return 'text/plain';
      case 'md':
      case 'markdown':
        return 'text/markdown';
      case 'json':
        return 'application/json';
      case 'csv':
        return 'text/csv';
      case 'tsv':
        return 'text/tab-separated-values';
      case 'xml':
        return 'application/xml';
      case 'yaml':
      case 'yml':
        return 'application/yaml';
      case 'pdf':
        return 'application/pdf';
      case 'zip':
        return 'application/zip';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'mp4':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      default:
        return null;
    }
  }

  /// Lowercase extension (no dot) of [name], or `null` when there is none.
  static String? extensionOf(String? name) {
    if (name == null) return null;
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return null;
    return name.substring(dot + 1).toLowerCase();
  }
}

/// A complete file object for an LLM-generated artifact: a document-style tile
/// with a type-specific icon (`.txt` renders as a generic text document, `.json`
/// as a data object, ...), the file name, and a save affordance. Tapping the
/// whole card triggers the export flow, mirroring the chat-export UX.
class ArtifactFileCard extends StatelessWidget {
  final String fileName;
  final String? fileMime;
  final VoidCallback? onOpen;
  final bool busy;
  final EdgeInsetsGeometry margin;

  const ArtifactFileCard({
    super.key,
    required this.fileName,
    this.fileMime,
    this.onOpen,
    this.busy = false,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final kind = FileArtifactStyle.kindFor(fileName, fileMime);
    final icon = FileArtifactStyle.iconFor(kind);
    final typeLabel = FileArtifactStyle.labelFor(kind);
    final accent = AppTheme.accentPrimary;

    final subtitle = [
      fileMime ?? typeLabel,
      'Tap to save',
    ].join(' · ');

    return Padding(
      padding: margin,
      child: Material(
        color: context.clanSurfaceVariant,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 22, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: context.clanTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.clanTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.download_rounded, size: 20, color: context.clanTextMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}