import 'package:postgres/postgres.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/features/offers/models/offer_receipt.dart';
import 'package:re_api/features/saved_parts/dto/save_part_request.dart';
import 'package:re_api/http/api_error.dart';

/// Persistencia de referencias y lectura del historial aisladas por RLS.
class SavedPartsRepository {
  /// Persistencia de referencias y lectura del historial aisladas por RLS.
  SavedPartsRepository(this.tx);

  /// Transacción autenticada del taller, sin conexiones adicionales.
  final TxSession tx;
  static const _select = '''
SELECT g.id_publico,g.proveedor,g.id_externo,g.tipo_referencia,g.enlace,g.nota,g.creado_en,
    d.codigo,c.nombre AS componente,u.nombre AS autor,ma.nombre AS marca,mo.nombre AS modelo,g.anio,
    s.id_publico AS sesion_id,v.id_publico AS vehiculo_id
    FROM public.repuesto_guardado g
    JOIN public.dtc_catalogo d ON d.id=g.dtc_id
    JOIN public.componente_repuesto c ON c.id=g.componente_id
    JOIN public.usuario u ON u.id=g.usuario_id AND u.taller_id=g.taller_id
    LEFT JOIN public.modelo_vehiculo mo ON mo.id=g.modelo_vehiculo_id
    LEFT JOIN public.marca_vehiculo ma ON ma.id=mo.marca_vehiculo_id
    LEFT JOIN public.sesion_diagnostico s ON s.id=g.sesion_id AND s.taller_id=g.taller_id
    LEFT JOIN public.vehiculo v ON v.id=g.vehiculo_id AND v.taller_id=g.taller_id''';
  Map<String, Object?> _json(ResultRow row) {
    final v = row.toColumnMap();
    return {
      'id': v['id_publico'],
      'provider': v['proveedor'],
      'external_id': v['id_externo'],
      'url': v['enlace'],
      'kind': v['tipo_referencia'],
      'note': v['nota'],
      'created_at': (v['creado_en']! as DateTime).toUtc().toIso8601String(),
      'dtc': v['codigo'],
      'component_name': v['componente'],
      'author': v['autor'],
      'brand': v['marca'],
      'model': v['modelo'],
      'year': v['anio'],
      'session_id': v['sesion_id'],
      'vehicle_id': v['vehiculo_id'],
      'compatibility': 'unverified',
    };
  }

  /// Recupera una selección previa sólo con igual solicitud y autor.
  Future<Map<String, Object?>?> retry(
    SavePartRequest input,
    AuthIdentity identity,
  ) async {
    final result = await tx.execute(
      Sql.named('''
      SELECT id_publico,hash_solicitud,usuario_id FROM public.repuesto_guardado WHERE clave_idempotencia=@key::uuid
    '''),
      parameters: {'key': input.key},
    );
    if (result.isEmpty) return null;
    if (result.single[1] != input.fingerprint ||
        result.single[2] != identity.userId) {
      throw const ApiError(409, 'idempotency_conflict');
    }
    return get(result.single[0]! as String);
  }

  /// Obtiene una selección visible por su UUID público.
  Future<Map<String, Object?>> get(String id) async {
    final result = await tx.execute(
      Sql.named('$_select WHERE g.id_publico=@id::uuid'),
      parameters: {'id': id},
    );
    if (result.isEmpty) throw const ApiError(404, 'saved_part_not_found');
    return _json(result.single);
  }

  /// Guarda una decisión validada sin comprar ni modificar el diagnóstico.
  Future<Map<String, Object?>> save(
    SavePartRequest input,
    OfferReceipt receipt,
    AuthIdentity identity,
  ) async {
    final plan = receipt.plan;
    late final Result result;
    try {
      result = await tx.execute(
        Sql.named('''
      INSERT INTO public.repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,modelo_vehiculo_id,anio,
        vehiculo_id,sesion_id,proveedor,id_externo,tipo_referencia,enlace,nota,clave_idempotencia,hash_solicitud)
      SELECT @workshop,@user,d.id,c.id,mo.id,@year,v.id,s.id,'mercadolibre',@external,@kind,@url,@note,@key::uuid,@hash
      FROM public.dtc_catalogo d
      JOIN public.dtc_componente dc ON dc.dtc_id=d.id
      JOIN public.componente_repuesto c ON c.id=dc.componente_id
      LEFT JOIN public.modelo_vehiculo mo ON mo.id_publico=@model::uuid
      LEFT JOIN public.vehiculo v ON v.id_publico=@vehicle::uuid
      LEFT JOIN public.sesion_diagnostico s ON s.id_publico=@session::uuid
      WHERE d.codigo=@code AND c.id_publico=@component::uuid
        AND (@vehicle::uuid IS NULL OR v.id IS NOT NULL)
        AND (@session::uuid IS NULL OR s.id IS NOT NULL)
        AND (@model::uuid IS NULL OR mo.id IS NOT NULL)
      ON CONFLICT(taller_id,clave_idempotencia) DO NOTHING RETURNING id_publico
    '''),
        parameters: {
          'workshop': identity.workshopId,
          'user': identity.userId,
          'year': plan.year,
          'external': receipt.offer.id,
          'kind': receipt.offer.kind,
          'url': receipt.offer.url,
          'note': input.note,
          'key': input.key,
          'hash': input.fingerprint,
          'model': plan.modelId,
          'vehicle': plan.vehicleId,
          'session': plan.sessionId,
          'code': plan.code,
          'component': plan.componentId,
        },
      );
    } on ServerException catch (error) {
      // El contexto puede cambiar entre la búsqueda y el guardado.
      if (error.code == '23503' || error.code == '23514') {
        throw const ApiError(409, 'invalid_saved_context');
      }
      rethrow;
    }
    if (result.isEmpty) {
      final existing = await retry(input, identity);
      if (existing != null) return existing;
      throw const ApiError(409, 'invalid_saved_context');
    }
    return get(result.single[0]! as String);
  }

  /// Página de referencias ordenadas por fecha e identificador.
  Future<Map<String, Object?>> list({
    required int limit,
    required int offset,
  }) async {
    final rows = await tx.execute(
      Sql.named(
        '$_select ORDER BY g.creado_en DESC,g.id DESC LIMIT '
        '@limit OFFSET @offset',
      ),
      parameters: {'limit': limit + 1, 'offset': offset},
    );
    return {
      'items': rows.take(limit).map(_json).toList(),
      'next_offset': rows.length > limit ? offset + limit : null,
    };
  }
}
