import 'package:re_api/features/diagnostics/models/session_status.dart';

/// Resumen del negocio, independiente de HTTP y del controlador PostgreSQL.
class DiagnosticSummary {
  /// Crea un resumen de una atención.
  const DiagnosticSummary({
    required this.id,
    required this.status,
    required this.startedAt,
    required this.method,
    required this.version,
    required this.userName,
    required this.faultCount,
    this.mileage,
    this.vehicleId,
    this.plate,
    this.year,
    this.model,
    this.brand,
    this.maxSeverity,
    this.quoteTotal,
    this.quoteCurrency,
  });

  /// UUID público de la sesión.
  final String id;

  /// Estado actual de la atención.
  final SessionStatus status;

  /// Fecha y hora de inicio en UTC.
  final DateTime startedAt;

  /// Origen del diagnóstico: manual u OBD Bluetooth.
  final String method;

  /// Versión para control de concurrencia.
  final int version;

  /// Nombre del usuario que registró la atención.
  final String userName;

  /// Cantidad de fallas registradas.
  final int faultCount;

  /// Kilometraje informado, si existe.
  final int? mileage;

  /// UUID público del vehículo, si es visible.
  final String? vehicleId;

  /// Patente del vehículo visible.
  final String? plate;

  /// Año del vehículo visible.
  final int? year;

  /// Modelo del vehículo visible.
  final String? model;

  /// Marca del vehículo visible.
  final String? brand;

  /// Mayor severidad registrada, si hay fallas.
  final String? maxSeverity;
  // Decimal exacto: no convertir importes monetarios a double.
  /// Importe decimal exacto de la cotización vigente.
  final String? quoteTotal;

  /// Moneda de la cotización vigente.
  final String? quoteCurrency;
}
