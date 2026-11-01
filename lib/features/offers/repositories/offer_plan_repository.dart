import 'package:postgres/postgres.dart';
import 'package:re_api/features/offers/dto/offer_search_request.dart';
import 'package:re_api/features/offers/models/offer_search_plan.dart';
import 'package:re_api/http/api_error.dart';

/// Consulta componentes y valida contexto usando RLS de la transacción.
class OfferPlanRepository {
  /// Consulta componentes y valida contexto usando RLS de la transacción.
  OfferPlanRepository(this._tx);
  final TxSession _tx;

  /// Lista candidatos de la falla, aunque no existan repuestos locales.
  Future<List<Map<String, Object?>>> components(String code) async {
    final rows = await _tx.execute(
      Sql.named('''
      SELECT c.id_publico,c.nombre FROM public.dtc_componente dc
      JOIN public.dtc_catalogo d ON d.id=dc.dtc_id
      JOIN public.componente_repuesto c ON c.id=dc.componente_id
      WHERE d.codigo=@code ORDER BY c.nombre,c.id
    '''),
      parameters: {'code': code},
    );
    return rows
        .map((r) => <String, Object?>{'id': r[0], 'name': r[1]})
        .toList();
  }

  /// Contexto de falla y vehículo revalidado en PostgreSQL.
  Future<OfferSearchPlan> plan(OfferSearchRequest input) async {
    final rows = await _tx.execute(
      Sql.named('''
      SELECT c.nombre FROM public.dtc_componente dc
      JOIN public.dtc_catalogo d ON d.id=dc.dtc_id
      JOIN public.componente_repuesto c ON c.id=dc.componente_id
      WHERE d.codigo=@code AND c.id_publico=@component::uuid
    '''),
      parameters: {'code': input.code, 'component': input.componentId},
    );
    if (rows.isEmpty) throw const ApiError(400, 'invalid_dtc_component');
    final name = rows.single[0]! as String;
    var vehicleQuery = '';
    if (input.modelId != null) {
      final models = await _tx.execute(
        Sql.named('''
        SELECT ma.nombre,mo.nombre FROM public.modelo_vehiculo mo
        JOIN public.marca_vehiculo ma ON ma.id=mo.marca_vehiculo_id
        WHERE mo.id_publico=@model::uuid
      '''),
        parameters: {'model': input.modelId},
      );
      if (models.isEmpty) throw const ApiError(400, 'invalid_model');
      vehicleQuery =
          ' ${models.single[0]} ${models.single[1]} ${input.year ?? ''}';
    }
    var vehicleId = input.vehicleId;
    if (input.sessionId != null) {
      final sessions = await _tx.execute(
        Sql.named('''
        SELECT v.id_publico FROM public.sesion_diagnostico s
        JOIN public.vehiculo v ON v.id=s.vehiculo_id AND v.taller_id=s.taller_id
        JOIN public.falla_sesion f ON f.sesion_id=s.id AND f.taller_id=s.taller_id
        JOIN public.dtc_catalogo d ON d.id=f.dtc_id
        WHERE s.id_publico=@session::uuid AND d.codigo=@code
      '''),
        parameters: {'session': input.sessionId, 'code': input.code},
      );
      if (sessions.isEmpty) {
        throw const ApiError(400, 'invalid_diagnostic_context');
      }
      final actual = sessions.first[0]! as String;
      if (vehicleId != null && vehicleId != actual) {
        throw const ApiError(400, 'invalid_vehicle_context');
      }
      vehicleId = actual;
    }
    if (vehicleId != null) {
      final vehicles = await _tx.execute(
        Sql.named('''
        SELECT 1 FROM public.vehiculo v JOIN public.modelo_vehiculo mo ON mo.id=v.modelo_vehiculo_id
        WHERE v.id_publico=@vehicle::uuid AND mo.id_publico=@model::uuid AND v.anio=@year
      '''),
        parameters: {
          'vehicle': vehicleId,
          'model': input.modelId,
          'year': input.year,
        },
      );
      if (vehicles.isEmpty) {
        throw const ApiError(400, 'invalid_vehicle_context');
      }
    }
    return OfferSearchPlan(
      code: input.code,
      componentId: input.componentId,
      componentName: name,
      query: '$name$vehicleQuery'.trim(),
      modelId: input.modelId,
      year: input.year,
      vehicleId: vehicleId,
      sessionId: input.sessionId,
    );
  }
}
