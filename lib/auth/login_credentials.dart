import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/http/api_error.dart';

/// Entrada del login: no admite ids de taller, usuario ni roles.
class LoginCredentials {
  const LoginCredentials._(this.email, this.password);

  /// Correo normalizado; la base vuelve a normalizarlo.
  final String email;

  /// Contraseña original; nunca se recorta ni se registra.
  final String password;

  /// Lee JSON limitado a 4 KiB y valida tipos antes de llamar a PostgreSQL.
  static Future<LoginCredentials> read(Request request) async {
    final contentType = request.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (contentType != 'application/json') {
      throw const ApiError(415, 'json_required');
    }
    final bytes = <int>[];
    await for (final chunk in request.bytes().timeout(
      const Duration(seconds: 5),
    )) {
      if (bytes.length + chunk.length > 4096) {
        throw const ApiError(413, 'payload_too_large');
      }
      bytes.addAll(chunk);
    }
    Object? body;
    try {
      body = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (_) {
      throw const ApiError(400, 'invalid_json');
    }
    if (body is! Map<String, dynamic> ||
        body.length != 2 ||
        body['email'] is! String ||
        body['password'] is! String) {
      throw const ApiError(400, 'invalid_credentials_payload');
    }
    final email = (body['email'] as String).trim().toLowerCase();
    final password = body['password'] as String;
    if (email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        email.codeUnits.any((value) => value < 32 || value == 127) ||
        password.isEmpty ||
        password.codeUnits.contains(0) ||
        utf8.encode(password).length > 72) {
      throw const ApiError(400, 'invalid_credentials_payload');
    }
    return LoginCredentials._(email, password);
  }
}
