/// Código DTC y sus referencias de catálogo.
class DiagnosticCode {
  /// Crea un código de falla conocido.
  const DiagnosticCode({
    required this.code,
    required this.description,
    required this.severity,
    required this.componentCount,
  });

  /// Código OBD normalizado.
  final String code;

  /// Descripción del catálogo.
  final String description;

  /// Severidad sugerida, no diagnóstico confirmado.
  final String severity;

  /// Cantidad de componentes asociados.
  final int componentCount;
}
