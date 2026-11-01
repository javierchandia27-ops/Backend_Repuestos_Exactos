import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/query_validation.dart';
import 'package:re_api/http/read_json_object.dart';

/// Alta mínima sin datos del titular; respeta la identificación técnica de SQL.
class RegisterVehicleRequest {
  RegisterVehicleRequest._(
    this.model,
    this.year,
    this.plate,
    this.engine,
    this.vin,
  );

  /// VIN opcional obtenido del escáner o declarado por el técnico.
  final String? vin;

  /// Modelo del catálogo.
  final String model;

  /// Año declarado por el técnico.
  final int year;

  /// Patente normalizada.
  final String plate;

  /// Motorización declarada, obligatoria cuando no se ingresa VIN.
  final String engine;

  /// Valida formato y rechaza claves ajenas al contrato.
  static Future<RegisterVehicleRequest> read(Request request) async {
    final b = await readObject(request, {
      'model_id',
      'year',
      'plate',
      'engine',
      'vin',
    });
    final model = b['model_id'];
    final year = b['year'];
    final plate = b['plate'];
    final engine = b['engine'];
    final rawVin = b['vin'];
    if (rawVin != null && rawVin is! String) {
      throw const ApiError(400, 'invalid_vin');
    }
    if (model is! String ||
        year is! int ||
        year < 1981 ||
        year > 2100 ||
        plate is! String ||
        engine is! String ||
        engine.trim().isEmpty ||
        engine.trim().length > 100) {
      throw const ApiError(400, 'invalid_vehicle');
    }
    final normalized = plate.trim().toUpperCase().replaceAll(
      RegExp(r'[-\s]'),
      '',
    );
    if (!RegExp(
      r'^(?:[A-Z]{2}[0-9]{4}|[BCDFGHJKLPRSTVWXYZ]{4}[0-9]{2})$',
    ).hasMatch(normalized)) {
      throw const ApiError(400, 'invalid_vehicle');
    }
    return RegisterVehicleRequest._(
      publicUuid(model),
      year,
      normalized,
      engine.trim(),
      rawVin == null ? null : vehicleVin(rawVin as String),
    );
  }
}
