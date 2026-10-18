/// Posición del historial. Nunca contiene identificadores internos.
class HistoryCursor {
  /// Identifica una sesión mediante fecha y UUID público.
  const HistoryCursor({required this.startedAt, required this.publicId});

  /// Fecha y hora de inicio en UTC.
  final DateTime startedAt;

  /// UUID público de la sesión que delimita la página.
  final String publicId;
}
