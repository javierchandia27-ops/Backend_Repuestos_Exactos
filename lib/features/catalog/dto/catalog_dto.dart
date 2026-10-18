import 'package:re_api/features/catalog/models/catalog_option.dart';
import 'package:re_api/features/catalog/models/catalog_part.dart';
import 'package:re_api/features/catalog/models/diagnostic_code.dart';

/// Contratos JSON de catálogo sin IDs internos ni precios base privados.
class CatalogDto {
  /// Serializa marcas o modelos.
  static Map<String, Object> options(List<CatalogOption> items) => {
    'data': items.map((v) => {'id_publico': v.id, 'nombre': v.name}).toList(),
  };

  /// Serializa sugerencias de códigos DTC.
  static Map<String, Object> codes(
    List<DiagnosticCode> items, {
    required bool hasMore,
  }) => {
    'data': items
        .map(
          (v) => {
            'codigo': v.code,
            'descripcion': v.description,
            'severidad_sugerida': v.severity,
            'componentes': v.componentCount,
          },
        )
        .toList(),
    'has_more': hasMore,
  };

  /// Serializa repuestos con importes enteros exactos como texto.
  static Map<String, Object?> parts(List<CatalogPart> items, int? nextOffset) =>
      {
        'data': items
            .map(
              (v) => {
                'id_publico': v.id,
                'componente_id_publico': v.componentId,
                'componente_nombre': v.componentName,
                'perfil': v.profile,
                'marca': v.brand,
                'nombre': v.name,
                'codigo_fabricante': v.manufacturerCode,
                'durabilidad_estimada_km': v.durability,
                'riesgo': v.risk,
                'precio_venta': v.salePrice,
                'moneda': v.currency,
              },
            )
            .toList(),
        'next_offset': nextOffset,
      };
}
