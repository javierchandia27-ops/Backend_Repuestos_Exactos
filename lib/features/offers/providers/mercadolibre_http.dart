import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:re_api/http/api_error.dart';

/// Sólo lo usan URLs fijas de la API oficial, nunca enlaces recibidos del
/// usuario.
Future<http.Response> mercadoLibreRequest(
  http.Client client,
  String method,
  Uri uri, {
  Map<String, String>? headers,
  Map<String, String>? fields,
}) async {
  final abort = Completer<void>();
  final timer = Timer(const Duration(seconds: 6), abort.complete);
  try {
    final req = http.AbortableRequest(method, uri, abortTrigger: abort.future);
    if (headers != null) req.headers.addAll(headers);
    if (fields != null) req.bodyFields = fields;
    final res = await client.send(req);
    final bytes = <int>[];
    await for (final chunk in res.stream) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) {
        if (!abort.isCompleted) abort.complete();
        throw const ApiError(502, 'provider_invalid_response');
      }
    }
    return http.Response(
      utf8.decode(bytes),
      res.statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  } on http.RequestAbortedException {
    throw const ApiError(504, 'provider_timeout');
  } on SocketException {
    throw const ApiError(502, 'provider_unavailable');
  } on http.ClientException {
    throw const ApiError(502, 'provider_unavailable');
  } on FormatException {
    throw const ApiError(502, 'provider_invalid_response');
  } finally {
    timer.cancel();
  }
}
