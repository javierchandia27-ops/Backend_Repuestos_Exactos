import 'package:re_api/features/diagnostics/dto/create_scan_request.dart';
import 'package:re_api/http/api_error.dart';
import 'package:test/test.dart';

void main() {
  Map<String, dynamic> body() => {
    'vehicle_id': '11111111-1111-4111-8111-111111111111',
    'device_id': '22222222-2222-4222-8222-222222222222',
    'idempotency_key': '33333333-3333-4333-8333-333333333333',
    'kilometraje': 1234,
    'captured_at': DateTime.now().toUtc().toIso8601String(),
    'protocol': 'ELM protocolo 6',
    'services': {'03': 'ok', '07': 'no_data', '0A': 'unsupported'},
    'observations': [
      {'code': 'P3999', 'ecu': '7E8', 'kind': 'stored'},
    ],
  };
  test('conserva desconocidos sin inventar descripción y normaliza huella', () {
    final b = body();
    final a = CreateScanRequest.parse(b);
    expect(a.observations.single['code'], 'P3999');
    final reordered = <String, dynamic>{
      for (final e in b.entries.toList().reversed) e.key: e.value,
    };
    expect(CreateScanRequest.parse(reordered).fingerprint, a.fingerprint);
  });
  test('rechaza categoría, conteo, identificadores y fecha inconsistentes', () {
    final variants = <Map<String, dynamic>>[
      {...body(), 'vehicle_id': 'bad'},
      {...body(), 'vin': 'INVALID'},
      {...body(), 'vin': '00000000000000000'},
      {...body(), 'vin': 123},
      {...body(), 'kilometraje': -1},
      {...body(), 'kilometraje': '1234'},
      {
        ...body(),
        'captured_at': DateTime.now()
            .toUtc()
            .add(const Duration(days: 1))
            .toIso8601String(),
      },
      {
        ...body(),
        'services': {'03': 'empty', '07': 'no_data', '0A': 'unsupported'},
      },
      {...body(), 'observations': <Map<String, String>>[]},
      {
        ...body(),
        'observations': [
          {'code': 'P3999', 'ecu': '7E8', 'kind': 'stored', 'title': 'forjado'},
        ],
      },
      {
        ...body(),
        'observations': [
          {'code': 'P3999', 'ecu': '7E8', 'kind': 'pending'},
        ],
      },
      {
        ...body(),
        'observations': [
          {'code': 'P3999', 'ecu': '7E8', 'kind': 'stored'},
          {'code': 'P3999', 'ecu': '7E8', 'kind': 'stored'},
        ],
      },
    ];
    for (final input in variants) {
      expect(() => CreateScanRequest.parse(input), throwsA(isA<ApiError>()));
    }
  });
  test(
    'conserva parciales opcionales pero exige modo 03 completo',
    () {
      final input = body();
      input['services'] = {'03': 'ok', '07': 'partial', '0A': 'unsupported'};
      (input['observations'] as List<Map<String, String>>).add(
        {'code': 'P0301', 'ecu': '7E8', 'kind': 'pending'},
      );
      expect(CreateScanRequest.parse(input).services['07'], 'partial');
      input['services'] = {
        '03': 'partial',
        '07': 'partial',
        '0A': 'unsupported',
      };
      expect(() => CreateScanRequest.parse(input), throwsA(isA<ApiError>()));
    },
  );
  test('VIN forma parte de la identidad de reintento y se normaliza', () {
    final input = body();
    final legacy = CreateScanRequest.parse(input);
    final withVin = CreateScanRequest.parse({
      ...input,
      'vin': ' vf300000000000001 ',
    });
    expect(withVin.vin, 'VF300000000000001');
    expect(withVin.fingerprint, isNot(legacy.fingerprint));
    expect(
      CreateScanRequest.parse({
        ...input,
        'vin': 'VF300000000000001',
      }).fingerprint,
      withVin.fingerprint,
    );
  });
  test('cero códigos válido no necesita una falla inventada', () {
    final input = CreateScanRequest.parse({
      ...body(),
      'services': {'03': 'empty', '07': 'empty', '0A': 'no_data'},
      'observations': <Map<String, String>>[],
    });
    expect(input.observations, isEmpty);
  });
}
