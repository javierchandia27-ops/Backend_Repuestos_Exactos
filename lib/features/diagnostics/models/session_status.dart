/// Estados persistidos de una atención de diagnóstico.
enum SessionStatus {
  /// Atención abierta sin cotización vigente.
  pendiente,

  /// Atención con cotización.
  cotizado,

  /// Atención terminada.
  completado,

  /// Atención cancelada.
  cancelado,
}
