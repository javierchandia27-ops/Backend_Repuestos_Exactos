/// El cursor ya no existe o no pertenece al contexto visible del taller.
class InvalidHistoryCursor implements Exception {
  /// No revela si la sesión pertenece a otro taller.
  const InvalidHistoryCursor();
}
