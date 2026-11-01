import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/http/api_error.dart';

/// Lee un objeto JSON con límite incremental y claves permitidas.
Future<Map<String, dynamic>> readObject(
  Request request,
  Set<String> keys, {
  int maxBytes = 8192,
}) async {
  if (request.headers['content-type']?.split(';').first.trim().toLowerCase() !=
      'application/json') {
    throw const ApiError(415, 'json_required');
  }
  final bytes = <int>[];
  await for (final chunk in request.bytes()) {
    if (bytes.length + chunk.length > maxBytes) {
      throw const ApiError(413, 'body_too_large');
    }
    bytes.addAll(chunk);
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
