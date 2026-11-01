import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/features/offers/dto/read_object.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/query_validation.dart';

/// Solicitud de selección con recibo, nota e idempotencia; sin precio del
/// cliente.
class SavePartRequest {
  /// Solicitud de selección con recibo, nota e idempotencia; sin precio del
  /// cliente.
  const SavePartRequest({
    required this.token,
    required this.key,
    required this.note,
  });

  /// Recibo opaco de un resultado consultado por el mismo usuario.
  final String token;

  /// UUID de idempotencia generado por el cliente para este intento.
  final String key;

  /// Observación del técnico, acotada a mil caracteres.
  final String note;

  /// Huella estable del recibo y nota para detectar reintentos incompatibles.
  String get fingerprint =>
      sha256.convert(utf8.encode(jsonEncode([token, note]))).toString();

  /// Lee JSON acotado y rechaza campos desconocidos o tipos inválidos.
  static Future<SavePartRequest> read(Request request) async {
    final body = await readObject(request, {
      'offer_token',
      'idempotency_key',
      'note',
    });
    final token = body['offer_token'];
    final key = body['idempotency_key'];
    final note = body['note'] ?? '';
    if (token is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token) ||
        key is! String ||
        note is! String ||
        note.length > 1000) {
      throw const ApiError(400, 'invalid_saved_part');
    }
    return SavePartRequest(
      token: token,
      key: publicUuid(key),
      note: note.trim(),
    );
  }
}
