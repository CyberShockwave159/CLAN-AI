/// Conditional-import facade for browser downloads.
///
/// The web variant triggers a browser download via a Blob URL; the io variant
/// is a stub that is never reached (the `kIsWeb` branch in [FileSaver] keeps
/// native platforms on their existing save paths).
library;

export 'browser_download_stub.dart'
    if (dart.library.js_interop) 'browser_download_web.dart'
    show browserDownload;