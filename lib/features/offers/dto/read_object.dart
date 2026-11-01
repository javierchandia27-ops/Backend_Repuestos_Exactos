import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/http/api_error.dart';

/// Límite incremental: no materializa cuerpos arbitrariamente grandes.
Future<Map<String, dynamic>> readObject(
  Request request,
  Set<String> keys,
) async {
  if (request.headers['content-type']?.split(';').first.trim().toLowerCase() !=
      'application/json') {
    throw const ApiError(415, 'json_required');
  }
  final bytes = <int>[];
  await for (final chunk in request.bytes()) {
    bytes.addAll(chunk);
    if (bytes.length > 8192) throw const ApiError(413, 'body_too_large');
  }
  try {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic> ||
        value.keys.any((k) => !keys.contains(k))) {
      throw const FormatException();
    }
    return value;
  } on FormatException {
    throw const ApiError(400, 'invalid_json');
  }
}
