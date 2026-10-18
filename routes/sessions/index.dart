import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/features/diagnostics/dto/diagnostic_history_dto.dart';
import 'package:re_api/features/diagnostics/dto/history_query.dart';
import 'package:re_api/features/diagnostics/models/invalid_history_cursor.dart';
import 'package:re_api/features/diagnostics/services/diagnostic_service.dart';
import 'package:re_api/http/api_error.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, headers: {'allow': 'GET'});
  }
  final query = HistoryQuery.parse(context.request.uri);
  try {
    final page = await context.read<DiagnosticService>().history(
      limit: query.limit,
      status: query.status,
      cursor: query.cursor,
    );
    return Response.json(body: DiagnosticHistoryDto.toJson(page));
  } on InvalidHistoryCursor catch (_) {
    throw const ApiError(400, 'invalid_cursor');
  }
}
