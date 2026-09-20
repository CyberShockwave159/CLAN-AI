/// Stub used on non-web platforms. Never reached — [FileSaver] short-circuits
/// to this only when `kIsWeb` is true, which implies the web variant resolves.
Future<String?> browserDownload({
  required String filename,
  required String content,
  required String mimeType,
}) {
  throw UnsupportedError('browserDownload is only supported on web');
}