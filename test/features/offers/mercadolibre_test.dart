import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/config/mercadolibre_config.dart';
import 'package:re_api/features/offers/models/offer_search_plan.dart';
import 'package:re_api/features/offers/providers/mercadolibre_provider.dart';
import 'package:re_api/features/offers/services/mercadolibre_tokens.dart';
import 'package:re_api/features/offers/services/offer_service.dart';
import 'package:re_api/http/api_error.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late MercadoLibreConfig config;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('meli-test-');
    config = MercadoLibreConfig(
      clientId: 'test-id',
      clientSecret: 'test-secret',
      tokenFile: '${dir.path}/tokens.json',
    );
    await MercadoLibreTokens.storeTokenResponse(
      config,
      jsonEncode({
        'access_token': 'test-access',
        'refresh_token': 'test-refresh',
        'expires_in': 3600,
      }),
    );
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  AuthIdentity identity(int user, int workshop) => AuthIdentity(
    userId: user,
    workshopId: workshop,
    userPublicId: 'u',
    workshopPublicId: 'w',
    role: UserRole.mecanico,
    name: 'Técnico',
  );
  final listing = {
    'id': 'MLC123456789',
    'title': 'Bobina de prueba',
    'price': 12345.5,
    'currency_id': 'CLP',
    'permalink': 'https://articulo.mercadolibre.cl/MLC-123456789-prueba',
  };
  test(
    'publicación: precio decimal, URL validada y recibo ligado a identidad',
    () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'api.mercadolibre.com');
        expect(request.headers['authorization'], 'Bearer test-access');
        return http.Response(
          jsonEncode({
            'results': [listing],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = OfferService(
        MercadoLibreProvider(MercadoLibreTokens(config, client), client),
      );
      final owner = identity(1, 1);
      final result = await service.search(
        owner,
        const OfferSearchPlan(
          code: 'P0301',
          componentId: 'c',
          componentName: 'Bobina',
          query: 'Bobina',
        ),
      );
      final offer = (result['items']! as List).single as Map;
      expect(offer['price'], '12345.5');
      expect(offer['compatibility'], 'unverified');
      final token = offer['offer_token'] as String;
      expect(service.receipt(token, owner).offer.id, 'MLC123456789');
      for (final other in [identity(2, 1), identity(1, 2)]) {
        expect(
          () => service.receipt(token, other),
          throwsA(
            isA<ApiError>().having((e) => e.code, 'code', 'offer_expired'),
          ),
        );
      }
    },
  );
  test(
    '403 de publicaciones permite catálogo autorizado, sin '
    'inventar precio ni enlace',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return request.url.path.endsWith('/search') &&
                request.url.path.startsWith('/sites/')
            ? http.Response('{}', 403)
            : http.Response(
                jsonEncode({
                  'results': [
                    {
                      'id': 'MLC12345678',
                      'name': 'Bujía técnica',
                      'status': 'inactive',
                    },
                  ],
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
      });
      final provider = MercadoLibreProvider(
        MercadoLibreTokens(config, client),
        client,
      );
      final result = await provider.search('Bujía');
      expect(result.single.kind, 'catalog_product');
      expect(result.single.catalogStatus, 'inactive');
      expect(result.single.price, isNull);
      expect(result.single.url, isNull);
      await provider.search('Bobina');
      expect(paths.where((p) => p == '/sites/MLC/search').length, 1);
    },
  );
  test(
    'no acepta URL de un tercero ni un precio adulterado del proveedor',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'results': [
              {
                ...listing,
                'permalink': 'https://mercadolibre.cl.attacker.example/product',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final provider = MercadoLibreProvider(
        MercadoLibreTokens(config, client),
        client,
      );
      await expectLater(
        provider.search('Bobina'),
        throwsA(
          isA<ApiError>().having(
            (e) => e.code,
            'code',
            'provider_invalid_response',
          ),
        ),
      );
    },
  );
  test(
    'renovaciones concurrentes usan una sola '
    'petición y conservan el refresh nuevo',
    () async {
      await File(config.tokenFile).writeAsString(
        jsonEncode({
          'access_token': 'expired',
          'refresh_token': 'old-refresh',
          'expires_at': '2000-01-01T00:00:00Z',
        }),
      );
      var calls = 0;
      final gate = Completer<void>();
      final client = MockClient((request) async {
        calls++;
        await gate.future;
        expect(request.bodyFields['refresh_token'], 'old-refresh');
        return http.Response(
          jsonEncode({
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
            'expires_in': 3600,
          }),
          200,
        );
      });
      final tokens = MercadoLibreTokens(config, client);
      final first = tokens.accessToken();
      final second = tokens.accessToken();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      gate.complete();
      expect(await Future.wait([first, second]), ['new-access', 'new-access']);
      expect(calls, 1);
      final stored =
          jsonDecode(await File(config.tokenFile).readAsString())
              as Map<String, dynamic>;
      expect(stored['refresh_token'], 'new-refresh');
      expect(await tokens.accessToken(), 'new-access');
      expect(calls, 1);
    },
  );
  test(
    'denegación y límite del proveedor no se confunden con PostgreSQL',
    () async {
      final denied = MockClient((_) async => http.Response('{}', 403));
      await expectLater(
        MercadoLibreProvider(
          MercadoLibreTokens(config, denied),
          denied,
        ).search('Bujía'),
        throwsA(
          isA<ApiError>().having(
            (e) => e.code,
            'code',
            'provider_access_denied',
          ),
        ),
      );
      final limited = MockClient((_) async => http.Response('{}', 429));
      await expectLater(
        MercadoLibreProvider(
          MercadoLibreTokens(config, limited),
          limited,
        ).search('Bujía'),
        throwsA(
          isA<ApiError>().having(
            (e) => e.code,
            'code',
            'provider_rate_limited',
          ),
        ),
      );
    },
  );
}
