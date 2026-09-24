/// Conditional-import facade that reloads the current page.
///
/// The web variant performs a hard browser reload; the io variant is a no-op
/// that keeps non-web platforms compiling without a crash (callers only ever
/// invoke it from the web-only update prompt).
library;

export 'web_page_reloader_stub.dart'
    if (dart.library.js_interop) 'web_page_reloader_web.dart'
    show reloadAppPage;