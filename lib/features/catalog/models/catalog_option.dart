/// Opción pública de marca o modelo del catálogo.
class CatalogOption {
  /// Crea una opción de selección.
  const CatalogOption({required this.id, required this.name});

  /// UUID público.
  final String id;

  /// Nombre de la marca o modelo.
  final String name;
}
