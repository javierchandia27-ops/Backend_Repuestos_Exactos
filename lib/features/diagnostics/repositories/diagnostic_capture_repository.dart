import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/features/diagnostics/dto/create_scan_request.dart';
import 'package:re_api/features/diagnostics/dto/register_vehicle_request.dart';
import 'package:re_api/http/api_error.dart';

/// Persistencia de capturas y selectores, siempre dentro de una transacción
/// RLS.
class DiagnosticCaptureRepository {
  /// Recibe la transacción autenticada.
  DiagnosticCaptureRepository(this.tx);

  /// Transacción del taller y usuario actuales.
  final TxSession tx;

  /// Vehículos visibles, sin información del titular.
  Future<List<Map<String, dynamic>>> vehicles({String? vin}) async =>
      (await tx.execute(
        Sql.named('''
    SELECT v.id_publico AS id,v.anio,mo.id_publico AS model_id,mo.nombre AS model,ma.nombre AS brand,v.patente AS plate,v.vin
    FROM public.vehiculo v JOIN public.modelo_vehiculo mo ON mo.id=v.modelo_vehiculo_id
    JOIN public.marca_vehiculo ma ON ma.id=mo.marca_vehiculo_id
    WHERE (@vin::text IS NULL OR v.vin=@vin) ORDER BY v.id DESC LIMIT 200
  '''),
        parameters: {'vin': vin},
      )).map((r) => r.toColumnMap()).toList();

  /// Alta o reintento de un vehículo, sin reemplazar registros existentes.
  Future<Map<String, dynamic>> registerVehicle(
    RegisterVehicleRequest input,
  ) async {
    final rows = await tx.execute(
      Sql.named('''
      INSERT INTO public.vehiculo(taller_id,modelo_vehiculo_id,anio,patente,motor,vin)
      SELECT public.fn_contexto_taller_id(),m.id,@year,@plate,@engine,@vin FROM public.modelo_vehiculo m
      WHERE m.id_publico=@model::uuid
      ON CONFLICT(taller_id,patente) WHERE patente IS NOT NULL DO NOTHING RETURNING id
    '''),
      parameters: {
        'model': input.model,
        'year': input.year,
        'plate': input.plate,
        'engine': input.engine,
        'vin': input.vin,
      },
    );
    final found = await tx.execute(
      Sql.named('''
      SELECT v.id_publico AS id,v.anio,mo.id_publico AS model_id,mo.nombre AS model,ma.nombre AS brand,v.patente AS plate,v.motor,v.vin
      FROM public.vehiculo v JOIN public.modelo_vehiculo mo ON mo.id=v.modelo_vehiculo_id
      JOIN public.marca_vehiculo ma ON ma.id=mo.marca_vehiculo_id WHERE v.patente=@plate
    '''),
      parameters: {'plate': input.plate},
    );
    if (found.isEmpty) throw const ApiError(404, 'vehicle_model_not_found');
    final r = found.single.toColumnMap();
    if (rows.isEmpty &&
        (r['model_id'] != input.model ||
            r['anio'] != input.year ||
            r['motor'] != input.engine ||
            (input.vin != null && r['vin'] != input.vin))) {
      throw const ApiError(409, 'vehicle_already_exists');
    }
    r.remove('motor');
    return r;
  }

  /// Inventario activo del taller; la MAC no se usa como identidad del
  /// navegador.
  Future<List<Map<String, dynamic>>> devices() async => (await tx.execute('''
    SELECT id_publico AS id,nombre AS name,modelo AS model FROM public.dispositivo_diagnostico
    WHERE estado='activo' ORDER BY id DESC LIMIT 200
  ''')).map((r) => r.toColumnMap()).toList();

  /// Alta idempotente lógica. La autorización de propietario se revalida en
  /// SQL.
  Future<Map<String, Object?>> registerDevice(String name, String key) async {
    final result = await tx.execute(
      Sql.named('''
      INSERT INTO public.dispositivo_diagnostico(taller_id,nombre,modelo,fabricante,clave_registro)
      VALUES(public.fn_contexto_taller_id(),@name,'vLinker MC','Vgate',@key::uuid)
      ON CONFLICT(taller_id,clave_registro) DO NOTHING RETURNING id_publico
    '''),
      parameters: {'name': name, 'key': key},
    );
    final found = await tx.execute(
      Sql.named('''
      SELECT id_publico,nombre FROM public.dispositivo_diagnostico WHERE clave_registro=@key::uuid
    '''),
      parameters: {'key': key},
    );
    if (found.isEmpty || found.single[1] != name) {
      throw const ApiError(409, 'idempotency_conflict');
    }
    return {
      'id': found.single[0],
      'name': found.single[1],
      'model': 'vLinker MC',
      'created': result.isNotEmpty,
    };
  }

  /// Devuelve un reintento únicamente si coinciden contenido y autor.
  Future<String?> retry(CreateScanRequest input, AuthIdentity user) async {
    final rows = await tx.execute(
      Sql.named('''
SELECT id_publico,hash_ingreso,usuario_id
      FROM public.sesion_diagnostico WHERE clave_ingreso=@key::uuid'''),
      parameters: {'key': input.key},
    );
    if (rows.isEmpty) return null;
    if (rows.single[1] != input.fingerprint || rows.single[2] != user.userId) {
      throw const ApiError(409, 'idempotency_conflict');
    }
    return rows.single[0]! as String;
  }

  /// No sustituye VIN existentes ni toma vehículos de otro taller. El bloqueo
  /// serializa capturas concurrentes antes de contrastar o completar el VIN.
  Future<void> _associateVin(CreateScanRequest input) async {
    final selected = await tx.execute(
      Sql.named('''
      SELECT id,vin FROM public.vehiculo
      WHERE id_publico=@id::uuid AND anonimizado_en IS NULL FOR UPDATE
    '''),
      parameters: {'id': input.vehicle},
    );
    if (selected.isEmpty) throw const ApiError(404, 'scan_context_not_found');
    final row = selected.single;
    if (row[1] != null && row[1] != input.vin) {
      throw const ApiError(409, 'vin_vehicle_mismatch');
    }
    if (row[1] == input.vin) return;
    try {
      await tx.execute(
        Sql.named('''
        UPDATE public.vehiculo SET vin=@vin WHERE id=@id
      '''),
        parameters: {'vin': input.vin, 'id': row[0]},
      );
    } on ServerException catch (e) {
      if (e.code == '23505') throw const ApiError(409, 'vehicle_vin_conflict');
      rethrow;
    }
  }

  /// Inserta sesión y todas las observaciones en la misma transacción.
  Future<String> create(CreateScanRequest input, AuthIdentity user) async {
    final previous = await retry(input, user);
    if (previous != null) return previous;
    if (input.vin != null) await _associateVin(input);
    final rows = await tx.execute(
      Sql.named('''
      INSERT INTO public.sesion_diagnostico(taller_id,vehiculo_id,usuario_id,dispositivo_id,metodo_ingreso,kilometraje,
        clave_ingreso,hash_ingreso,capturada_en,protocolo_obd,servicios_obd)
      SELECT public.fn_contexto_taller_id(),v.id,public.fn_contexto_usuario_id(),d.id,'obd_bluetooth',@km,
        @key::uuid,@hash,@captured,@protocol,@services::jsonb
      FROM public.vehiculo v CROSS JOIN public.dispositivo_diagnostico d
      WHERE v.id_publico=@vehicle::uuid AND d.id_publico=@device::uuid AND d.estado='activo'
      ON CONFLICT(taller_id,clave_ingreso) DO NOTHING RETURNING id,id_publico
    '''),
      parameters: {
        'km': input.mileage,
        'key': input.key,
        'hash': input.fingerprint,
        'captured': input.capturedAt,
        'protocol': input.protocol,
        'services': jsonEncode(input.services),
        'vehicle': input.vehicle,
        'device': input.device,
      },
    );
    if (rows.isEmpty) {
      final concurrent = await retry(input, user);
      if (concurrent != null) return concurrent;
      throw const ApiError(404, 'scan_context_not_found');
    }
    await tx.execute(
      Sql.named('''
      INSERT INTO public.observacion_obd(sesion_id,taller_id,ecu,codigo,categoria)
      SELECT @session,public.fn_contexto_taller_id(),x.ecu,x.code,x.kind
      FROM jsonb_to_recordset(@observations::jsonb) AS x(ecu text,code text,kind text)
    '''),
      parameters: {
        'session': rows.single[0],
        'observations': jsonEncode(input.observations),
      },
    );
    await tx.execute(
      Sql.named('''
      INSERT INTO public.falla_sesion(sesion_id,taller_id,dtc_id,severidad)
      SELECT DISTINCT o.sesion_id,o.taller_id,d.id,d.severidad_sugerida
      FROM public.observacion_obd o JOIN public.dtc_catalogo d ON d.codigo=o.codigo
      WHERE o.sesion_id=@session
    '''),
      parameters: {'session': rows.single[0]},
    );
    return rows.single[1]! as String;
  }

  /// Detalle visible con todas las ECU/categorías y descripciones
  /// autoritativas.
  Future<Map<String, Object?>> detail(String id) async {
    final rows = await tx.execute(
      Sql.named('''
      SELECT s.id,s.id_publico,s.kilometraje,s.iniciada_en,s.capturada_en,s.protocolo_obd,s.servicios_obd,
        v.id_publico AS vehicle_id,v.anio,v.vin,mo.id_publico AS model_id,mo.nombre AS model,ma.nombre AS brand
      FROM public.sesion_diagnostico s LEFT JOIN public.vehiculo v ON v.id=s.vehiculo_id AND v.taller_id=s.taller_id
      LEFT JOIN public.modelo_vehiculo mo ON mo.id=v.modelo_vehiculo_id LEFT JOIN public.marca_vehiculo ma ON ma.id=mo.marca_vehiculo_id
      WHERE s.id_publico=@id::uuid
    '''),
      parameters: {'id': id},
    );
    if (rows.isEmpty) throw const ApiError(404, 'diagnostic_not_found');
    final r = rows.single.toColumnMap();
    final observations = await tx.execute(
      Sql.named('''
      SELECT o.codigo AS code,o.ecu,o.categoria AS kind,d.descripcion AS description
      FROM public.observacion_obd o LEFT JOIN public.dtc_catalogo d ON d.codigo=o.codigo
      WHERE o.sesion_id=@session ORDER BY o.codigo,o.ecu,o.categoria
    '''),
      parameters: {'session': r['id']},
    );
    final items = observations.map((r) => r.toColumnMap()).toList();
    if (r['protocolo_obd'] == null) {
      final legacy = await tx.execute(
        Sql.named(
          '''
SELECT d.codigo AS code,NULL::text AS ecu,NULL::text AS kind,d.descripcion AS description
        FROM public.falla_sesion f JOIN public.dtc_catalogo d ON d.id=f.dtc_id WHERE f.sesion_id=@id ORDER BY d.codigo''',
        ),
        parameters: {'id': r['id']},
      );
      items.addAll(legacy.map((r) => r.toColumnMap()));
    }
    return {
      'id': r['id_publico'],
      'vehicle_id': r['vehicle_id'],
      'vin': r['vin'],
      'model_id': r['model_id'],
      'brand': r['brand'],
      'model': r['model'],
      'year': r['anio'],
      'kilometraje': r['kilometraje'],
      'created_at': (r['iniciada_en']! as DateTime).toUtc().toIso8601String(),
      'captured_at': (r['capturada_en'] as DateTime?)
          ?.toUtc()
          .toIso8601String(),
      'protocol': r['protocolo_obd'],
      'services': r['servicios_obd'],
      'observations': items,
    };
  }
}
