import 'package:postgres/postgres.dart';
import 'package:re_api/features/catalog/models/catalog_option.dart';
import 'package:re_api/features/catalog/models/catalog_part.dart';
import 'package:re_api/features/catalog/models/diagnostic_code.dart';

/// Catálogos globales y precios calculados bajo el contexto del taller.
class CatalogRepository {
  /// Recibe la transacción autenticada; no abre conexiones adicionales.
  CatalogRepository(this._transaction);
  final TxSession _transaction;

  /// Marcas disponibles, según q02 de RE-db.
  Future<List<CatalogOption>> brands() async {
    final rows = await _transaction.execute('''
      SELECT id_publico, nombre FROM public.marca_vehiculo ORDER BY nombre, id
    ''');
    return rows
        .map(
          (row) =>
              CatalogOption(id: row[0]! as String, name: row[1]! as String),
        )
        .toList();
  }

  /// Modelos de una marca pública.
  Future<List<CatalogOption>> models(String brand) async {
    final rows = await _transaction.execute(
      Sql.named('''
      SELECT mo.id_publico, mo.nombre FROM public.modelo_vehiculo mo
      JOIN public.marca_vehiculo ma ON ma.id = mo.marca_vehiculo_id
      WHERE ma.id_publico = @brand::uuid ORDER BY mo.nombre, mo.id
    '''),
      parameters: {'brand': brand},
    );
    return rows
        .map(
          (row) =>
              CatalogOption(id: row[0]! as String, name: row[1]! as String),
        )
        .toList();
  }

  /// Búsqueda por prefijo DTC normalizado y límite.
  Future<List<DiagnosticCode>> codes(String prefix, int limit) async {
    final rows = await _transaction.execute(
      Sql.named('''
      SELECT d.codigo, d.descripcion, d.severidad_sugerida::text,
        (SELECT count(*) FROM public.dtc_componente dc WHERE dc.dtc_id = d.id)
      FROM public.dtc_catalogo d WHERE d.codigo LIKE @prefix || '%'
      ORDER BY d.codigo LIMIT @limit
    '''),
      parameters: {'prefix': prefix, 'limit': limit},
    );
    return rows
        .map(
          (row) => DiagnosticCode(
            code: row[0]! as String,
            description: row[1]! as String,
            severity: row[2]! as String,
            componentCount: row[3]! as int,
          ),
        )
        .toList();
  }

  /// Verifica un DTC completo sin convertir ausencia de repuestos en error.
  Future<bool> hasCode(String code) async {
    final rows = await _transaction.execute(
      Sql.named('''
      SELECT 1 FROM public.dtc_catalogo WHERE codigo = @code
    '''),
      parameters: {'code': code},
    );
    return rows.isNotEmpty;
  }

  /// Repuestos disponibles, compatibilidad RN-44 y margen actual RN-45.
  Future<List<CatalogPart>> parts(
    String code, {
    required int limit,
    required int offset,
    String? model,
    int? year,
  }) async {
    final rows = await _transaction.execute(
      Sql.named('''
      SELECT c.id_publico AS componente_id_publico, c.nombre AS componente_nombre,
        r.id_publico, r.perfil::text AS perfil, r.marca, r.nombre,
        r.codigo_fabricante, r.durabilidad_estimada_km, r.riesgo::text AS riesgo,
        ROUND(r.precio_referencia * (1 + tc.margen_pct / 100))::bigint::text AS precio_venta,
        tc.moneda
      FROM public.dtc_catalogo d
      JOIN public.v_dtc_repuesto x ON x.dtc_id = d.id
      JOIN public.componente_repuesto c ON c.id = x.componente_id
      JOIN public.repuesto r ON r.id = x.repuesto_id
      CROSS JOIN public.taller_configuracion tc
      WHERE d.codigo = @code AND r.disponible
      AND (@model::uuid IS NULL OR EXISTS (
        SELECT 1 FROM public.compatibilidad_repuesto k
        JOIN public.modelo_vehiculo mo ON mo.id = k.modelo_vehiculo_id
        WHERE k.repuesto_id = r.id AND mo.id_publico = @model::uuid
          AND (@year::smallint IS NULL OR @year::smallint BETWEEN k.anio_desde AND k.anio_hasta)
      ))
      ORDER BY c.nombre, c.id,
        CASE r.perfil WHEN 'genuino' THEN 1 WHEN 'oem' THEN 2 WHEN 'generico' THEN 3 END,
        ROUND(r.precio_referencia * (1 + tc.margen_pct / 100))::bigint, r.id
      LIMIT @limit OFFSET @offset
    '''),
      parameters: {
        'code': code,
        'model': model,
        'year': year,
        'limit': limit,
        'offset': offset,
      },
    );
    return rows.map((row) {
      final v = row.toColumnMap();
      return CatalogPart(
        id: v['id_publico']! as String,
        componentId: v['componente_id_publico']! as String,
        componentName: v['componente_nombre']! as String,
        profile: v['perfil']! as String,
        brand: v['marca']! as String,
        name: v['nombre']! as String,
        manufacturerCode: v['codigo_fabricante']! as String,
        durability: v['durabilidad_estimada_km']! as int,
        risk: v['riesgo']! as String,
        salePrice: v['precio_venta']! as String,
        currency: v['moneda']! as String,
      );
    }).toList();
  }
}
