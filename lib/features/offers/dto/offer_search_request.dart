import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/features/offers/dto/read_object.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/query_validation.dart';

/// Filtros de búsqueda validados antes de consultar SQL o al proveedor.
class OfferSearchRequest {
  /// Filtros de búsqueda validados antes de consultar SQL o al proveedor.
  const OfferSearchRequest({
    required this.code,
    required this.componentId,
    this.modelId,
    this.year,
    this.vehicleId,
    this.sessionId,
  });

  /// Código DTC normalizado del catálogo local.
  final String code;

  /// UUID público del componente candidato asociado a la falla.
  final String componentId;

  /// UUID público del modelo opcional.
  final String? modelId;

  /// UUID del vehículo visible en el taller, si se seleccionó por VIN.
  final String? vehicleId;

  /// UUID de diagnóstico opcional, validado contra la falla y el vehículo.
  final String? sessionId;

  /// Año del vehículo; requiere modelo.
  final int? year;

  /// Lee JSON acotado y rechaza campos desconocidos o tipos inválidos.
  static Future<OfferSearchRequest> read(Request request) async {
    final body = await readObject(request, {
      'dtc',
      'component_id',
      'model',
      'year',
      'vehicle_id',
      'session_id',
    });
    if (body['dtc'] is! String || body['component_id'] is! String) {
      throw const ApiError(400, 'invalid_offer_search');
    }
    String? uuid(String key) {
      final v = body[key];
      if (v == null) return null;
      if (v is! String) throw const ApiError(400, 'invalid_id');
      return publicUuid(v);
    }

    final model = uuid('model');
    final year = body['year'];
    if (year != null &&
        (year is! int || year < 1981 || year > 2100 || model == null)) {
      throw const ApiError(400, 'invalid_offer_search');
    }
    return OfferSearchRequest(
      code: diagnosticCode(body['dtc'] as String),
      componentId: publicUuid(body['component_id'] as String),
      modelId: model,
      year: year as int?,
      vehicleId: uuid('vehicle_id'),
      sessionId: uuid('session_id'),
    );
  }
}
