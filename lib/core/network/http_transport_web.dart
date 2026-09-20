import 'dart:async';
import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'streamed_api_response.dart';

/// Web transport built on the browser `fetch` API.
///
/// The browser fetch never exposes a "connect phase", so the client type here
/// is just the `http` default (based on `BrowserClient` for non-streaming
/// calls that may still go through `ApiHttpClient`'s `_client`).
http.Client createHttpClient(Duration connectTimeout) => http.Client();

/// Streams [request] via `fetch`, resolving as soon as response headers arrive
/// and pumping the body through an abortable stream.
///
/// Cancellation is wired end-to-end: when the consumer stops listening (for
/// example stop-generation aborting the SSE stream), the underlying fetch is
/// aborted with `AbortController`, exactly mirroring how dart:io's
/// `HttpClient` tears down the socket.
Future<StreamedApiResponse> streamSend(
    http.Client client, http.BaseRequest request) async {
  final controller = StreamController<List<int>>();
  final abortController = web.AbortController();

  var cancelled = false;
  controller.onCancel = () {
    cancelled = true;
    abortController.abort();
  };

  final headers = web.Headers();
  request.headers.forEach((key, value) => headers.set(key, value));

  final body = request is http.Request ? request.body : null;

  final response = await web.window
      .fetch(
        web.Request(
          request.url.toString().toJS,
          web.RequestInit(
            method: request.method,
            headers: headers,
            body: body?.toJS,
            signal: abortController.signal,
          ),
        ),
      )
      .toDart;

  final statusCode = response.status;
  final stream = response.body;
  final reader = stream != null ? web.ReadableStreamDefaultReader(stream) : null;

  unawaited(() async {
    try {
      if (reader != null) {
        while (true) {
          final result = await reader.read().toDart;
          if (result.done) break;
          final value = result.value;
          if (value != null) {
            controller.add((value as JSUint8Array).toDart);
          }
        }
      }
      await controller.close();
    } catch (e) {
      if (!cancelled && !controller.isClosed) {
        controller.addError(e);
        await controller.close();
      }
    }
  }());

  return StreamedApiResponse(statusCode, controller.stream);
}