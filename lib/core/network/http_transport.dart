/// Conditional-import facade for the HTTP transport.
///
/// `createHttpClient` and `streamSend` are implemented per platform:
/// - io: real `HttpClient` with a true TCP/TLS connect timeout, `send`-based
///   streaming (`lib/core/network/http_transport_io.dart`).
/// - web: browser fetch + ReadableStream reader, abortable on cancel
///   (`lib/core/network/http_transport_web.dart`).
library;

export 'http_transport_stub.dart'
    if (dart.library.js_interop) 'http_transport_web.dart'
    if (dart.library.io) 'http_transport_io.dart'
    show createHttpClient, streamSend;