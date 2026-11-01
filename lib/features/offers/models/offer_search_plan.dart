/// Contexto validado en PostgreSQL antes de consultar al proveedor.
class OfferSearchPlan {
  /// Contexto preparado en SQL antes del trabajo HTTP externo.
  const OfferSearchPlan({
    required this.code,
    required this.componentId,
    required this.componentName,
    required this.query,
    this.modelId,
    this.year,
    this.vehicleId,
    this.sessionId,
  });

  /// Código DTC normalizado del catálogo local.
  final String code;

  /// UUID público del componente candidato asociado a la falla.
  final String componentId;

  /// Nombre del componente candidato; no es un diagnóstico confirmado.
  final String componentName;

  /// Consulta construida con componente, marca, modelo y año disponibles.
  final String query;

  /// UUID público del modelo opcional.
  final String? modelId;

  /// UUID del vehículo visible en el taller, si se seleccionó por VIN.
  final String? vehicleId;

  /// UUID de diagnóstico opcional, validado contra la falla y el vehículo.
  final String? sessionId;

  /// Año del vehículo; requiere modelo.
  final int? year;
}
