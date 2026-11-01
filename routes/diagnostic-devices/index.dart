import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/features/diagnostics/repositories/diagnostic_capture_repository.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/query_validation.dart';
import 'package:re_api/http/read_json_object.dart';

Future<Response> onRequest(RequestContext context) async {
  final repository = DiagnosticCaptureRepository(context.read<TxSession>());
  validateQueryKeys(context.request.uri, {});
  if (context.request.method == HttpMethod.get) {
    return Response.json(body: {'items': await repository.devices()});
  }
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, headers: {'allow': 'GET, POST'});
  }
  if (context.read<AuthSession>().identity.role != UserRole.propietario) {
    throw const ApiError(403, 'owner_required');
  }
  final body = await readObject(context.request, {'name', 'idempotency_key'});
  final name = body['name'];
  final key = body['idempotency_key'];
  if (name is! String ||
      name.trim().isEmpty ||
      name.trim().length > 80 ||
      key is! String) {
    throw const ApiError(400, 'invalid_device');
  }
  return Response.json(
    body: await repository.registerDevice(name.trim(), publicUuid(key)),
  );
}
