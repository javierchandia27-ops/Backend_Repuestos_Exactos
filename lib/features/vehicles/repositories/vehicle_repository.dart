import 'package:postgres/postgres.dart';
import 'package:re_api/features/vehicles/models/vehicle_match.dart';

/// Consulta vehículos dentro de la transacción y las políticas del taller.
class VehicleRepository {
  /// Recibe la transacción autenticada.
  VehicleRepository(this._transaction);
  final TxSession _transaction;

  /// Busca un VIN exacto; RLS oculta otros talleres y vehículos restringidos.
  Future<VehicleMatch?> byVin(String vin) async {
    // Proyección mínima de q03: no leer titular ni sus datos personales.
    final rows = await _transaction.execute(
      Sql.named('''
      SELECT v.id_publico, v.vin, v.patente, v.anio,
        mo.id_publico AS modelo_id_publico, mo.nombre AS modelo_nombre,
        ma.id_publico AS marca_id_publico, ma.nombre AS marca_nombre
      FROM public.vehiculo v
      JOIN public.modelo_vehiculo mo ON mo.id = v.modelo_vehiculo_id
      JOIN public.marca_vehiculo ma ON ma.id = mo.marca_vehiculo_id
      WHERE v.vin = @vin
    '''),
      parameters: {'vin': vin},
    );
    if (rows.isEmpty) return null;
    final v = rows.single.toColumnMap();
    return VehicleMatch(
      id: v['id_publico']! as String,
      vin: v['vin']! as String,
      plate: v['patente']! as String,
      year: v['anio']! as int,
      modelId: v['modelo_id_publico']! as String,
      modelName: v['modelo_nombre']! as String,
      brandId: v['marca_id_publico']! as String,
      brandName: v['marca_nombre']! as String,
    );
  }
}
