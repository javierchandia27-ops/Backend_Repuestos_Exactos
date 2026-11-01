import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/features/offers/dto/offer_search_request.dart';
import 'package:re_api/features/saved_parts/dto/save_part_request.dart';
import 'package:re_api/http/api_error.dart';
import 'package:test/test.dart';

void main() {
  Request request(Map<String, Object?> body) => Request.post(
    Uri.parse('http://localhost/offers/search'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode(body),
  );
  test(
    'no acepta campos de autoridad ni precios fijados por el cliente',
    () async {
      for (final field in [
        'taller_id',
        'usuario_id',
        'price',
        'url',
        'provider',
      ]) {
        await expectLater(
          SavePartRequest.read(
            request({
              'offer_token': 'a' * 43,
              'idempotency_key': '11111111-1111-4111-8111-111111111111',
              field: 'forged',
            }),
          ),
          throwsA(isA<ApiError>()),
        );
      }
    },
  );
  test('valida la combinación modelo/año antes de consultar SQL', () async {
    await expectLater(
      OfferSearchRequest.read(
        request({
          'dtc': 'P0301',
          'component_id': '11111111-1111-4111-8111-111111111111',
          'year': 2016,
        }),
      ),
      throwsA(isA<ApiError>()),
    );
  });
  test('rechaza cuerpos demasiado grandes', () async {
    await expectLater(
      SavePartRequest.read(request({'note': 'x' * 9000})),
      throwsA(isA<ApiError>().having((e) => e.statusCode, 'status', 413)),
    );
  });
}
