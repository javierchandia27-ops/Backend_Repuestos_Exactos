import 'package:re_api/features/vehicles/models/vehicle_match.dart';
import 'package:re_api/features/vehicles/repositories/vehicle_repository.dart';

/// Punto de entrada a la identificación de vehículos registrados.
class VehicleService {
  /// Inyecta el repositorio del taller.
  VehicleService(this._repository);
  final VehicleRepository _repository;

  /// Devuelve solo una coincidencia visible; no decodifica VIN externos.
  Future<VehicleMatch?> byVin(String vin) => _repository.byVin(vin);
}
