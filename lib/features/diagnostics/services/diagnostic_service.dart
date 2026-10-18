import 'package:re_api/features/diagnostics/models/diagnostic_history_page.dart';
import 'package:re_api/features/diagnostics/models/history_cursor.dart';
import 'package:re_api/features/diagnostics/models/invalid_history_cursor.dart';
import 'package:re_api/features/diagnostics/models/session_status.dart';
import 'package:re_api/features/diagnostics/repositories/diagnostic_repository.dart';

/// Coordina validación del ancla y paginación del historial.
class DiagnosticService {
  /// Recibe el acceso a datos del contexto actual.
  DiagnosticService(this._repository);
  final DiagnosticRepository _repository;

  /// Solicita una fila adicional para determinar si hay otra página.
  Future<DiagnosticHistoryPage> history({
    required int limit,
    SessionStatus? status,
    HistoryCursor? cursor,
  }) async {
    if (cursor != null && !await _repository.containsCursor(cursor)) {
      throw const InvalidHistoryCursor();
    }
    final rows = await _repository.history(
      limit: limit + 1,
      status: status,
      cursor: cursor,
    );
    final items = rows.take(limit).toList(growable: false);
    final last = items.isEmpty ? null : items.last;
    return DiagnosticHistoryPage(
      items: List.unmodifiable(items),
      nextCursor: rows.length > limit && last != null
          ? HistoryCursor(startedAt: last.startedAt, publicId: last.id)
          : null,
    );
  }
}
