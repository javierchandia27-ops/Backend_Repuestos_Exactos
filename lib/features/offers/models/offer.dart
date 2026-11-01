/// Oferta temporal: la compatibilidad requiere revisión del técnico.
class Offer {
  /// Resultado temporal validado del proveedor; no confirma compatibilidad.
  const Offer({
    required this.id,
    required this.title,
    required this.price,
    required this.currency,
    required this.url,
    required this.queriedAt,
    this.kind = 'listing',
    this.catalogStatus,
  });

  /// Identificador externo del proveedor, sin convertirlo en repuesto interno.
  final String id;

  /// Nombre devuelto por el proveedor; no se archiva en el historial.
  final String title;

  /// Precio decimal publicado; null para referencias técnicas sin oferta.
  final String? price;

  /// Moneda del precio publicado; null si no existe precio.
  final String? currency;

  /// Enlace HTTPS validado de una publicación; null para catálogo técnico.
  final String? url;

  /// Distingue publicación comercial de referencia técnica de catálogo.
  final String kind;

  /// Estado active/inactive del catálogo, sin inferir stock.
  final String? catalogStatus;

  /// Momento UTC de consulta al proveedor.
  final DateTime queriedAt;

  /// Respuesta pública sin credenciales ni información interna.
  Map<String, Object?> toJson() => {
    'provider': 'mercadolibre',
    'kind': kind,
    'catalog_status': catalogStatus,
    'external_id': id,
    'title': title,
    'price': price,
    'currency': currency,
    'url': url,
    'queried_at': queriedAt.toUtc().toIso8601String(),
    'compatibility': 'unverified',
  };
}
