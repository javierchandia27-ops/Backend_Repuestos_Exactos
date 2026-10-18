/// Vehículo visible del taller, sin datos del titular.
class VehicleMatch {
  /// Crea una coincidencia por VIN.
  const VehicleMatch({
    required this.id,
    required this.vin,
    required this.plate,
    required this.year,
    required this.modelId,
    required this.modelName,
    required this.brandId,
    required this.brandName,
  });

  /// UUID público del vehículo.
  final String id;

  /// Número VIN registrado.
  final String vin;

  /// Patente registrada.
  final String plate;

  /// Año del vehículo.
  final int year;

  /// UUID público del modelo.
  final String modelId;

  /// Nombre del modelo.
  final String modelName;

  /// UUID público de la marca.
  final String brandId;

  /// Nombre de la marca.
  final String brandName;
}
