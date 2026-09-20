import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'streamed_api_response.dart';

/// Builds a client with a *real* TCP/TLS connect timeout.
///
/// `Future.timeout` bounds a whole request, so it cannot tell a stalled TCP
/// connect apart from slow response data. `HttpClient.connectionTimeout`
/// covers the connect/TLS phase; the per-request `.timeout(...)` guards in
/// `ApiHttpClient` continue to bound the receive phase.
http.Client createHttpClient(Duration connectTimeout) {
  final httpClient = HttpClient()..connectionTimeout = connectTimeout;
  return IOClient(httpClient);
}

/// Sends [request] with [client], resolving once the response *headers* arrive
/// (before the body is consumed). The response body stays streamed.
Future<StreamedApiResponse> streamSend(
    http.Client client, http.BaseRequest request) async {
  final response = await client.send(request);
  return StreamedApiResponse(response.statusCode, response.stream);
}