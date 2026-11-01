import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/query_validation.dart';
import 'package:re_api/http/read_json_object.dart';

/// Captura completa validada; el cliente nunca asigna taller, autor ni estado.
class CreateScanRequest {
  CreateScanRequest._(
    this.vehicle,
    this.device,
    this.mileage,
    this.key,
    this.capturedAt,
    this.protocol,
    this.services,
    this.observations,
    this.vin,
  );

  /// Valida datos antes de abrir escrituras SQL.
  factory CreateScanRequest.parse(Map<String, dynamic> b) {
    Never invalid() => throw const ApiError(400, 'invalid_scan');
    String id(String k) {
      final v = b[k];
      if (v is! String) invalid();
      return publicUuid(v);
    }

    final rawVin = b['vin'];
    if (rawVin != null && rawVin is! String) invalid();
    final vin = rawVin == null ? null : vehicleVin(rawVin as String);
    final mileage = b['kilometraje'];
    final protocol = b['protocol'];
    final when = b['captured_at'];
    if (mileage is! int ||
        mileage < 0 ||
        mileage > 2147483647 ||
        protocol is! String ||
        protocol.trim().isEmpty ||
        protocol.length > 120 ||
        when is! String) {
      invalid();
    }
    final time = DateTime.tryParse(when);
    final now = DateTime.now().toUtc();
    if (time == null ||
        !time.isUtc ||
        time.isAfter(now.add(const Duration(minutes: 5))) ||
        time.isBefore(now.subtract(const Duration(days: 7)))) {
      invalid();
    }
    final rawServices = b['services'];
    if (rawServices is! Map<String, dynamic> ||
        rawServices.length != 3 ||
        !rawServices.keys.toSet().containsAll({'03', '07', '0A'})) {
      invalid();
    }
    final services = <String, String>{};
    for (final k in ['03', '07', '0A']) {
      final v = rawServices[k];
      if (v is! String ||
          !{'ok', 'empty', 'no_data', 'unsupported', 'partial'}.contains(v)) {
        invalid();
      }
      services[k] = v;
    }
    if (!{'ok', 'empty'}.contains(services['03'])) invalid();
    final raw = b['observations'];
    if (raw is! List || raw.length > 256) invalid();
    final observations = <Map<String, String>>[];
    final seen = <String>{};
    for (final value in raw) {
      if (value is! Map<String, dynamic> ||
          value.length != 3 ||
          !value.keys.toSet().containsAll({'code', 'ecu', 'kind'})) {
        invalid();
      }
      final o = value;
      final code = o['code'];
      final ecu = o['ecu'];
      final kind = o['kind'];
      if (code is! String ||
          ecu is! String ||
          !RegExp(r'^[0-9A-F]{2,8}$').hasMatch(ecu) ||
          kind is! String ||
          !{'stored', 'pending', 'permanent'}.contains(kind)) {
        invalid();
      }
      final mode = {'stored': '03', 'pending': '07', 'permanent': '0A'}[kind];
      if (!{'ok', 'partial'}.contains(services[mode])) invalid();
      final normalized = diagnosticCode(code);
      if (!seen.add('$ecu|$normalized|$kind')) invalid();
      observations.add({
        'code': normalized,
        'ecu': ecu,
        'kind': kind,
      });
    }
    for (final e in {
      '03': 'stored',
      '07': 'pending',
      '0A': 'permanent',
    }.entries) {
      if (services[e.key] == 'ok' &&
          !observations.any((o) => o['kind'] == e.value)) {
        invalid();
      }
    }
    observations.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
    return CreateScanRequest._(
      id('vehicle_id'),
      id('device_id'),
      mileage,
      id('idempotency_key'),
      time,
      protocol.trim(),
      services,
      observations,
      vin,
    );
  }

  /// VIN observado por OBD; opcional y contrastado con el vehículo al guardar.
  final String? vin;

  /// Vehículo visible del taller.
  final String vehicle;

  /// Adaptador registrado por el propietario.
  final String device;

  /// Kilometraje declarado por el técnico.
  final int mileage;

  /// Clave estable por intento lógico de guardado.
  final String key;

  /// Fecha de lectura; la fecha de persistencia se genera en el servidor.
  final DateTime capturedAt;

  /// Protocolo detectado.
  final String protocol;

  /// Estado explícito de cada consulta.
  final Map<String, String> services;

  /// Observaciones normalizadas y ordenadas, incluidas las no catalogadas.
  final List<Map<String, String>> observations;

  /// Lee JSON limitado y valida también objetos anidados.
  static Future<CreateScanRequest> read(Request request) async =>
      CreateScanRequest.parse(
        await readObject(request, {
          'vehicle_id',
          'device_id',
          'kilometraje',
          'idempotency_key',
          'captured_at',
          'protocol',
          'services',
          'observations',
          'vin',
        }, maxBytes: 32768),
      );

  /// Huella canónica para resolver reintentos y conflictos.
  String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'vehicle': vehicle,
            if (vin != null) 'vin': vin,
            'device': device,
            'mileage': mileage,
            'captured': capturedAt.toIso8601String(),
            'protocol': protocol,
            'services': services,
            'observations': observations,
          }),
        ),
      )
      .toString();
}
