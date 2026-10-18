import 'package:re_api/features/diagnostics/models/diagnostic_summary.dart';
import 'package:re_api/features/diagnostics/models/history_cursor.dart';

/// Página estable del historial de diagnósticos.
class DiagnosticHistoryPage {
  /// Agrupa resultados y su continuación.
  const DiagnosticHistoryPage({required this.items, this.nextCursor});

  /// Resultados visibles de esta página.
  final List<DiagnosticSummary> items;

  /// Última posición cuando quedan más resultados.
  final HistoryCursor? nextCursor;
}
