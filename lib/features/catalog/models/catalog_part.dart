/// Repuesto de catálogo con precio de venta del taller actual.
class CatalogPart {
  /// Crea un resultado de catálogo.
  const CatalogPart({
    required this.id,
    required this.componentId,
    required this.componentName,
    required this.profile,
    required this.brand,
    required this.name,
    required this.manufacturerCode,
    required this.durability,
    required this.risk,
    required this.salePrice,
    required this.currency,
  });

  /// UUID público del repuesto.
  final String id;

  /// UUID público del componente.
  final String componentId;

  /// Nombre del componente.
  final String componentName;

  /// Perfil: genuino, oem o generico.
  final String profile;

  /// Fabricante o marca.
  final String brand;

  /// Nombre del repuesto.
  final String name;

  /// Referencia del fabricante.
  final String manufacturerCode;

  /// Durabilidad estimada por catálogo en kilómetros.
  final int durability;

  /// Riesgo referencial del catálogo.
  final String risk;

  /// Importe entero exacto, serializado sin pérdida de precisión en web.
  final String salePrice;

  /// Moneda configurada en el taller.
  final String currency;
}
