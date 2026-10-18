import 'package:postgres/postgres.dart';
import 'package:re_api/features/diagnostics/models/diagnostic_summary.dart';
import 'package:re_api/features/diagnostics/models/history_cursor.dart';
import 'package:re_api/features/diagnostics/models/session_status.dart';

/// Usa exclusivamente la transacción autenticada proporcionada por middleware.
class DiagnosticRepository {
  /// Recibe una transacción con rol y taller ya establecidos.
  DiagnosticRepository(this._transaction);
  final TxSession _transaction;

  /// Comprueba el ancla aplicando las mismas políticas RLS del listado.
  Future<bool> containsCursor(HistoryCursor cursor) async {
    final rows = await _transaction.execute(
      Sql.named('''
      SELECT 1 FROM public.sesion_diagnostico
      WHERE id_publico = @cursor_id::uuid AND iniciada_en = @cursor_date::timestamptz
    '''),
      parameters: {
        'cursor_id': cursor.publicId,
        'cursor_date': cursor.startedAt,
      },
    );
    return rows.isNotEmpty;
  }

  /// Ejecuta las variantes del contrato q04 con parámetros enlazados.
  Future<List<DiagnosticSummary>> history({
    required int limit,
    SessionStatus? status,
    HistoryCursor? cursor,
  }) async {
    // Las cuatro variantes de q04_sesiones conservan la condición de índice.
    // Solo se concatenan fragmentos constantes; los valores son parámetros.
    final conditions = <String>[
      if (status != null) 's.estado = @status::public.tipo_estado_atencion',
      if (cursor != null)
        '''
        (s.iniciada_en, s.id) <
        (@cursor_date::timestamptz, (SELECT k.id FROM public.sesion_diagnostico k
          WHERE k.id_publico = @cursor_id::uuid))''',
    ];
    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final rows = await _transaction.execute(
      Sql.named('''
      SELECT s.id_publico, s.estado::text AS estado, s.iniciada_en,
             s.metodo_ingreso::text AS metodo_ingreso, s.kilometraje, s.version,
             v.id_publico AS vehiculo_id_publico, v.patente AS vehiculo_patente,
             v.anio AS vehiculo_anio, mo.nombre AS modelo_nombre,
             ma.nombre AS marca_nombre, u.nombre AS usuario_nombre,
             f.fallas, f.severidad_maxima, c.total::text AS cotizacion_total,
             c.moneda AS cotizacion_moneda
      FROM public.sesion_diagnostico s
      JOIN public.usuario u ON u.id = s.usuario_id
      LEFT JOIN public.vehiculo v ON v.id = s.vehiculo_id
      LEFT JOIN public.modelo_vehiculo mo ON mo.id = v.modelo_vehiculo_id
      LEFT JOIN public.marca_vehiculo ma ON ma.id = mo.marca_vehiculo_id
      LEFT JOIN public.cotizacion c ON c.sesion_id = s.id AND c.vigente
      CROSS JOIN LATERAL (
        SELECT count(*) AS fallas, max(x.severidad)::text AS severidad_maxima
        FROM public.falla_sesion x WHERE x.sesion_id = s.id
      ) f
      $where
      ORDER BY s.iniciada_en DESC, s.id DESC
      LIMIT @limit
    '''),
      parameters: {
        'limit': limit,
        if (status != null) 'status': status.name,
        if (cursor != null) 'cursor_date': cursor.startedAt,
        if (cursor != null) 'cursor_id': cursor.publicId,
      },
    );
    return rows.map((row) {
      final v = row.toColumnMap();
      return DiagnosticSummary(
        id: v['id_publico']! as String,
        status: SessionStatus.values.byName(v['estado']! as String),
        startedAt: (v['iniciada_en']! as DateTime).toUtc(),
        method: v['metodo_ingreso']! as String,
        version: v['version']! as int,
        userName: v['usuario_nombre']! as String,
        faultCount: v['fallas']! as int,
        mileage: v['kilometraje'] as int?,
        vehicleId: v['vehiculo_id_publico'] as String?,
        plate: v['vehiculo_patente'] as String?,
        year: v['vehiculo_anio'] as int?,
        model: v['modelo_nombre'] as String?,
        brand: v['marca_nombre'] as String?,
        maxSeverity: v['severidad_maxima'] as String?,
        quoteTotal: v['cotizacion_total'] as String?,
        quoteCurrency: v['cotizacion_moneda'] as String?,
      );
    }).toList();
  }
}
