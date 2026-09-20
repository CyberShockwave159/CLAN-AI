import 'dart:async';

import 'package:http/http.dart' as http;

import 'streamed_api_response.dart';

/// Stub used on platforms without a real transport (never reached: the io and
/// web variants of `http_transport.dart` take precedence via conditional
/// imports).
http.Client createHttpClient(Duration connectTimeout) {
  throw UnsupportedError(
      'createHttpClient is not supported on this platform');
}

Future<StreamedApiResponse> streamSend(
    http.Client client, http.BaseRequest request) {
  throw UnsupportedError('streamSend is not supported on this platform');
}