import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/query_validation.dart';

/// Filtros de compatibilidad y página de repuestos.
class PartSearchQuery {
  /// Define filtros validados.
  const PartSearchQuery({
    this.model,
    this.year,
    this.limit = 20,
    this.offset = 0,
  });

  /// Valida el contrato de búsqueda de repuestos.
  factory PartSearchQuery.parse(Uri uri) {
    validateQueryKeys(uri, {'model', 'year', 'limit', 'offset'});
    final values = uri.queryParameters;
    final model = values['model'] == null ? null : publicUuid(values['model']!);
    final year = values['year'] == null
        ? null
        : queryInteger(values['year'], fallback: 1981, min: 1981, max: 2100);
    if (year != null && model == null) {
      throw const ApiError(400, 'year_requires_model');
    }
    return PartSearchQuery(
      model: model,
      year: year,
      limit: queryInteger(values['limit'], fallback: 20, min: 1, max: 100),
      offset: queryInteger(values['offset'], fallback: 0, min: 0, max: 1000000),
    );
  }

  /// UUID público del modelo opcional.
  final String? model;

  /// Año opcional; requiere un modelo.
  final int? year;

  /// Tamaño de página.
  final int limit;

  /// Posición de lectura en el catálogo ordenado.
  final int offset;
}
