import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/features/diagnostics/dto/create_scan_request.dart';
import 'package:re_api/features/diagnostics/dto/diagnostic_history_dto.dart';
import 'package:re_api/features/diagnostics/dto/history_query.dart';
import 'package:re_api/features/diagnostics/models/invalid_history_cursor.dart';
import 'package:re_api/features/diagnostics/repositories/diagnostic_capture_repository.dart';
import 'package:re_api/features/diagnostics/services/diagnostic_capture_service.dart';
import 'package:re_api/features/diagnostics/services/diagnostic_service.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/query_validation.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method == HttpMethod.post) {
    validateQueryKeys(context.request.uri, {});
    final input = await CreateScanRequest.read(context.request);
    return Response.json(
      body: await DiagnosticCaptureService(
        DiagnosticCaptureRepository(context.read<TxSession>()),
      ).save(input, context.read<AuthSession>().identity),
    );
  }
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, headers: {'allow': 'GET, POST'});
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
