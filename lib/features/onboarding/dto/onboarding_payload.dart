import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/http/api_error.dart';

/// Lectura acotada y validación de los campos permitidos.
class OnboardingPayload {
  /// Rechaza claves desconocidas y cuerpos excesivos.
  static Future<Map<String, dynamic>> read(
    Request request,
    Set<String> allowed,
  ) async {
    if (request.headers['content-type']
            ?.split(';')
            .first
            .trim()
            .toLowerCase() !=
        'application/json') {
      throw const ApiError(415, 'json_required');
    }
    final bytes = <int>[];
    await for (final chunk in request.bytes().timeout(
      const Duration(seconds: 5),
    )) {
      if (bytes.length + chunk.length > 12288) {
        throw const ApiError(413, 'payload_too_large');
      }
      bytes.addAll(chunk);
    }
    try {
      final body = jsonDecode(utf8.decode(bytes));
      if (body is! Map<String, dynamic> ||
          body.keys.any((k) => !allowed.contains(k))) {
        throw const FormatException();
      }
      return body;
    } on FormatException {
      throw const ApiError(400, 'invalid_payload');
    }
  }

  /// Extrae una cadena requerida y limita su tamaño.
  static String text(
    Map<String, dynamic> body,
    String key, {
    int min = 1,
    int max = 8192,
  }) {
    final value = body[key];
    if (value is! String ||
        value.length < min ||
        value.length > max ||
        value.codeUnits.contains(0)) {
      throw const ApiError(400, 'invalid_payload');
    }
    return value;
  }
}
