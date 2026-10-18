import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/features/vehicles/dto/vehicle_dto.dart';
import 'package:re_api/features/vehicles/repositories/vehicle_repository.dart';
import 'package:re_api/features/vehicles/services/vehicle_service.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/query_validation.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, headers: {'allow': 'GET'});
  }
  // Misma separación de permisos de q03: auditoría usa el catálogo global.
  if (context.read<AuthSession>().identity.role == UserRole.auditor) {
    return apiError(403, 'vehicle_search_forbidden');
  }
  validateQueryKeys(context.request.uri, {'vin'});
  final vin = context.request.uri.queryParameters['vin']?.trim().toUpperCase();
  if (vin == null || !RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(vin)) {
    throw const ApiError(400, 'invalid_vin');
  }
  final service = VehicleService(VehicleRepository(context.read<TxSession>()));
  return Response.json(body: VehicleDto.toJson(await service.byVin(vin)));
}
