import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/features/diagnostics/repositories/diagnostic_capture_repository.dart';
import 'package:re_api/http/query_validation.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, headers: {'allow': 'GET'});
  }
  validateQueryKeys(context.request.uri, {});
  return Response.json(
    body: await DiagnosticCaptureRepository(
      context.read<TxSession>(),
    ).detail(publicUuid(id)),
  );
}
