import 'dart:convert';

import 'package:re_api/features/diagnostics/models/history_cursor.dart';
import 'package:re_api/features/diagnostics/models/session_status.dart';
import 'package:re_api/http/api_error.dart';

/// Contrato HTTP de listado: parámetros cerrados y paginación acotada.
class HistoryQuery {
  /// Define filtros y tamaño de página ya validados.
  const HistoryQuery({this.limit = 20, this.status, this.cursor});

  /// Valida los parámetros permitidos en la URI.
  factory HistoryQuery.parse(Uri uri) {
    final values = uri.queryParametersAll;
    if (values.keys.any(
          (key) => !{'limit', 'status', 'cursor'}.contains(key),
        ) ||
        values.values.any((value) => value.length != 1)) {
      throw const ApiError(400, 'invalid_query');
    }
    final limitText = uri.queryParameters['limit'];
    final limit = limitText == null ? 20 : int.tryParse(limitText);
    if (limit == null ||
        limit < 1 ||
        limit > 100 ||
        (limitText != null && !RegExp(r'^[0-9]+$').hasMatch(limitText))) {
      throw const ApiError(400, 'invalid_limit');
    }
    final statusText = uri.queryParameters['status'];
    SessionStatus? status;
    if (statusText != null) {
      for (final value in SessionStatus.values) {
        if (value.name == statusText) status = value;
      }
      if (status == null) throw const ApiError(400, 'invalid_status');
    }
    final cursorText = uri.queryParameters['cursor'];
    return HistoryQuery(
      limit: limit,
      status: status,
      cursor: cursorText == null ? null : decodeCursor(cursorText),
    );
  }

  /// Cantidad de resultados solicitados, entre 1 y 100.
  final int limit;

  /// Estado actual de la atención.
  final SessionStatus? status;

  /// Posición de continuación dentro del taller autenticado.
  final HistoryCursor? cursor;

  static final _uuid = RegExp(
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Decodifica y valida un cursor opaco recibido por HTTP.
  static HistoryCursor decodeCursor(String value) {
    try {
      if (value.isEmpty ||
          value.length > 512 ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
        throw const FormatException();
      }
      final json = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(value))),
      );
      if (json is! Map<String, dynamic> ||
          json.length != 2 ||
          json['id'] is! String ||
          json['date'] is! String) {
        throw const FormatException();
      }
      final id = json['id'] as String;
      final dateText = json['date'] as String;
      final date = DateTime.tryParse(dateText);
      if (!_uuid.hasMatch(id) ||
          date == null ||
          !date.isUtc ||
          date.year < 1 ||
          date.year > 9999 ||
          date.toIso8601String() != dateText) {
        throw const FormatException();
      }
      return HistoryCursor(startedAt: date, publicId: id);
    } on FormatException catch (_) {
      throw const ApiError(400, 'invalid_cursor');
    }
  }

  /// Genera el cursor público de la siguiente página.
  static String encodeCursor(HistoryCursor cursor) => base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'date': cursor.startedAt.toUtc().toIso8601String(),
            'id': cursor.publicId,
          }),
        ),
      )
      .replaceAll('=', '');
}
