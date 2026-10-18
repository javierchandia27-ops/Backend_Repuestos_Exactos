import 'package:re_api/features/vehicles/models/vehicle_match.dart';

/// Proyección pública mínima del vehículo encontrado.
class VehicleDto {
  /// Conserva null cuando no hay coincidencia visible.
  static Map<String, Object?> toJson(VehicleMatch? value) => {
    'data': value == null
        ? null
        : {
            'id_publico': value.id,
            'vin': value.vin,
            'patente': value.plate,
            'anio': value.year,
            'modelo_id_publico': value.modelId,
            'modelo_nombre': value.modelName,
            'marca_id_publico': value.brandId,
            'marca_nombre': value.brandName,
          },
  };
}
