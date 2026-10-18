import 'dart:convert';
import 'dart:math';

/// Metadatos de auditoría generados por el servidor.
class RequestMetadata {
  /// Genera el identificador; la IP debe proceder del socket del servidor.
  factory RequestMetadata.create({String? ip}) {
    final random = Random.secure();
    final requestId = base64UrlEncode(
      List<int>.generate(16, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    return RequestMetadata._(ip, requestId);
  }
  const RequestMetadata._(this.ip, this.requestId);

  /// IP de la conexión directa, o null para pruebas sin socket.
  final String? ip;

  /// Identificador no controlado por el cliente.
  final String requestId;
}
