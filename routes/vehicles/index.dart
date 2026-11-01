import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/features/diagnostics/dto/register_vehicle_request.dart';
import 'package:re_api/features/diagnostics/repositories/diagnostic_capture_repository.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/query_validation.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method == HttpMethod.post) {
    validateQueryKeys(context.request.uri, {});
    try {
      return Response.json(
        body: await DiagnosticCaptureRepository(
          context.read<TxSession>(),
        ).registerVehicle(await RegisterVehicleRequest.read(context.request)),
      );
    } on ServerException catch (e) {
      if (e.code == '23505') throw const ApiError(409, 'vehicle_vin_conflict');
      rethrow;
    }
  }
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, headers: {'allow': 'GET, POST'});
  }
  validateQueryKeys(context.request.uri, {'vin'});
  final vin = context.request.uri.queryParameters['vin'];
  return Response.json(
    body: {
      'items': await DiagnosticCaptureRepository(
        context.read<TxSession>(),
      ).vehicles(vin: vin == null ? null : vehicleVin(vin)),
    },
  );
}
