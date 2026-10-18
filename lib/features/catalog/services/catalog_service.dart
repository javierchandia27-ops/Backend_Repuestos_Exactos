import 'package:re_api/features/catalog/models/catalog_option.dart';
import 'package:re_api/features/catalog/models/catalog_part.dart';
import 'package:re_api/features/catalog/models/diagnostic_code.dart';
import 'package:re_api/features/catalog/repositories/catalog_repository.dart';

/// Coordina las lecturas y la paginación del catálogo.
class CatalogService {
  /// Inyecta el repositorio del contexto actual.
  CatalogService(this._repository);
  final CatalogRepository _repository;

  /// Lista marcas públicas.
  Future<List<CatalogOption>> brands() => _repository.brands();

  /// Lista modelos de la marca elegida.
  Future<List<CatalogOption>> models(String brand) => _repository.models(brand);

  /// Busca códigos y detecta si conviene refinar el prefijo.
  Future<({List<DiagnosticCode> items, bool hasMore})> codes(
    String prefix,
    int limit,
  ) async {
    final rows = await _repository.codes(prefix, limit + 1);
    return (
      items: List<DiagnosticCode>.unmodifiable(rows.take(limit)),
      hasMore: rows.length > limit,
    );
  }

  /// Indica si el código existe en el catálogo.
  Future<bool> hasCode(String code) => _repository.hasCode(code);

  /// Obtiene una página de repuestos y su continuación.
  Future<({List<CatalogPart> items, int? nextOffset})> parts(
    String code, {
    required int limit,
    required int offset,
    String? model,
    int? year,
  }) async {
    final rows = await _repository.parts(
      code,
      model: model,
      year: year,
      limit: limit + 1,
      offset: offset,
    );
    return (
      items: List<CatalogPart>.unmodifiable(rows.take(limit)),
      nextOffset: rows.length > limit ? offset + limit : null,
    );
  }
}
