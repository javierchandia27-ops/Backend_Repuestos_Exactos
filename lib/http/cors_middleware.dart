import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:dotenv/dotenv.dart';
import 'package:re_api/http/api_error.dart';

/// Orígenes explícitos de la aplicación web local o del despliegue.
Set<String> loadCorsOrigins() {
  final dotenv = DotEnv(quiet: true)..load();
  final value =
      Platform.environment['CORS_ALLOWED_ORIGINS'] ??
      dotenv['CORS_ALLOWED_ORIGINS'] ??
      'http://localhost:8080,http://127.0.0.1:8080';
  final origins = value.split(',').map((item) => item.trim()).toSet();
  if (origins.any((item) {
    final uri = Uri.tryParse(item);
    return uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isNotEmpty;
  })) {
    throw const FormatException(
      'CORS_ALLOWED_ORIGINS requiere orígenes exactos.',
    );
  }
  return origins;
}

/// Resuelve preflight sin abrir una sesión ni consultar PostgreSQL.
Middleware corsMiddleware(Set<String> allowedOrigins) => (handler) {
  return (context) async {
    final request = context.request;
    final origin = request.headers['origin'];
    if (origin == null) return handler(context);
    if (!allowedOrigins.contains(origin)) {
      return apiError(
        403,
        'origin_not_allowed',
      ).copyWith(headers: {'vary': 'Origin'});
    }
    final headers = <String, Object>{
      'access-control-allow-origin': origin,
      'vary': 'Origin',
    };
    if (request.method == HttpMethod.options) {
      final method = request.headers['access-control-request-method'];
      final requestedHeaders =
          request.headers['access-control-request-headers']
              ?.split(',')
              .map((item) => item.trim().toLowerCase()) ??
          <String>[];
      if (!{'GET', 'POST'}.contains(method) ||
          requestedHeaders.any(
            (item) => !{'authorization', 'content-type'}.contains(item),
          )) {
        return apiError(
          403,
          'preflight_not_allowed',
        ).copyWith(headers: headers);
      }
      return Response(
        statusCode: 204,
        headers: {
          ...headers,
          'access-control-allow-methods': 'GET, POST, OPTIONS',
          'access-control-allow-headers': 'Authorization, Content-Type',
          'access-control-max-age': '600',
        },
      );
    }
    final response = await handler(context);
    return response.copyWith(headers: headers);
  };
};
