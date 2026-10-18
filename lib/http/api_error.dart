import 'package:dart_frog/dart_frog.dart';

/// Error HTTP controlado, sin detalles privados de la infraestructura.
class ApiError implements Exception {
  /// Define el código HTTP y un identificador público fijo.
  const ApiError(this.statusCode, this.code);

  /// Código HTTP.
  final int statusCode;

  /// Identificador público del error.
  final String code;
}

/// Respuesta uniforme para errores, sin almacenar credenciales en caché.
Response apiError(int statusCode, String code) => Response.json(
  statusCode: statusCode,
  headers: {
    'cache-control': 'no-store',
    if (statusCode == 401) 'www-authenticate': 'Bearer',
  },
  body: {'error': code},
);
