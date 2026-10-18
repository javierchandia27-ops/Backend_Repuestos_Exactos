import 'package:re_api/features/diagnostics/dto/history_query.dart';
import 'package:re_api/features/diagnostics/models/diagnostic_history_page.dart';
import 'package:re_api/features/diagnostics/models/diagnostic_summary.dart';

/// Serializa el contrato público del historial.
class DiagnosticHistoryDto {
  /// Convierte entidades y cursor a una respuesta JSON.
  static Map<String, Object?> toJson(DiagnosticHistoryPage page) => {
    'data': page.items.map(_summary).toList(),
    'next_cursor': page.nextCursor == null
        ? null
        : HistoryQuery.encodeCursor(page.nextCursor!),
  };

  static Map<String, Object?> _summary(DiagnosticSummary item) => {
    'id_publico': item.id,
    'estado': item.status.name,
    'iniciada_en': item.startedAt.toUtc().toIso8601String(),
    'metodo_ingreso': item.method,
    'kilometraje': item.mileage,
    'version': item.version,
    'usuario_nombre': item.userName,
    'vehiculo_id_publico': item.vehicleId,
    'vehiculo_patente': item.plate,
    'vehiculo_anio': item.year,
    'modelo_nombre': item.model,
    'marca_nombre': item.brand,
    'fallas': item.faultCount,
    'severidad_maxima': item.maxSeverity,
    'cotizacion_total': item.quoteTotal,
    'cotizacion_moneda': item.quoteCurrency,
  };
}
