import 'package:re_api/http/api_error.dart';

/// Rechaza filtros desconocidos o repetidos antes de consultar la base.
void validateQueryKeys(Uri uri, Set<String> allowed) {
  if (uri.queryParametersAll.keys.any((key) => !allowed.contains(key)) ||
      uri.queryParametersAll.values.any((values) => values.length != 1)) {
    throw const ApiError(400, 'invalid_query');
  }
}

/// Valida un entero acotado recibido por HTTP.
int queryInteger(
  String? text, {
  required int fallback,
  required int min,
  required int max,
}) {
  if (text == null) return fallback;
  final value = int.tryParse(text);
  if (!RegExp(r'^[0-9]+$').hasMatch(text) ||
      value == null ||
      value < min ||
      value > max) {
    throw const ApiError(400, 'invalid_query');
  }
  return value;
}

/// Acepta solamente UUID públicos con formato completo.
String publicUuid(String value) {
  if (!RegExp(
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value)) {
    throw const ApiError(400, 'invalid_id');
  }
  return value.toLowerCase();
}

/// Normaliza un DTC completo o un prefijo permitido por el catálogo.
String diagnosticCode(String value, {bool prefix = false}) {
  final code = value.trim().toUpperCase();
  final pattern = prefix
      ? r'^(?:[PCBU](?:[0-3][0-9A-F]{0,3})?)?$'
      : r'^[PCBU][0-3][0-9A-F]{3}$';
  if (!RegExp(pattern).hasMatch(code)) {
    throw const ApiError(400, 'invalid_dtc');
  }
  return code;
}
