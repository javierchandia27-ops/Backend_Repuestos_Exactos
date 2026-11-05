import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/config/ebay_config.dart';
import 'package:re_api/features/offers/models/offer_search_plan.dart';
import 'package:re_api/features/offers/providers/ebay_provider.dart';
import 'package:re_api/features/offers/providers/provider_http.dart';
import 'package:re_api/features/offers/services/ebay_tokens.dart';
import 'package:re_api/features/offers/services/offer_service.dart';
import 'package:re_api/http/api_error.dart';
import 'package:test/test.dart';

const config = EbayConfig(clientId: 'qa-id', clientSecret: 'qa-secret');
const item = <String, Object?>{
  'itemId': 'v1|110590963673|0',
  'title': 'Bujía de prueba',
  'price': {'value': '5.00', 'currency': 'USD'},
  'buyingOptions': ['FIXED_PRICE'],
  'itemWebUrl': 'https://sandbox.ebay.com/itm/110590963673',
};
http.Response json(Object? data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Matcher apiError(String code) =>
    isA<ApiError>().having((e) => e.code, 'code', code);
void main() {
  test(
    'Sandbox autentica, conserva decimales y traduce sólo el componente',
    () async {
      final client = MockClient((r) async {
        expect(r.url.host, 'api.sandbox.ebay.com');
        if (r.url.path.endsWith('/token')) {
          expect(r.bodyFields, {
            'grant_type': 'client_credentials',
            'scope': 'https://api.ebay.com/oauth/api_scope',
          });
          expect(
            r.headers['authorization'],
            'Basic ${base64Encode(utf8.encode('qa-id:qa-secret'))}',
          );
          return json({'access_token': 'qa-access', 'expires_in': 7200});
        }
        expect(r.url.queryParameters['limit'], '20');
        expect(r.headers['X-EBAY-C-MARKETPLACE-ID'], 'EBAY_US');
        expect(r.headers['authorization'], 'Bearer qa-access');
        return json({
          'total': 1,
          'itemSummaries': [item],
        });
      });
      addTearDown(client.close);
      final provider = EbayProvider(EbayTokens(config, client), client);
      expect(
        provider.queryFor(
          const OfferSearchPlan(
            code: 'P0301',
            componentId: 'c',
            componentName: 'Bujía',
            query: 'Bujía Peugeot 3008 2017',
          ),
        ),
        'spark plug Peugeot 3008 2017',
      );
      final result = (await provider.search('spark plug')).single;
      expect(result.price, '5.00');
      expect(result.currency, 'USD');
      expect(result.provider, 'ebay');
      expect(result.environment, 'sandbox');
      expect(result.toJson()['compatibility'], 'unverified');
      expect(result.toJson().containsKey('seller'), isFalse);
      expect(await provider.search('🚗' * 100), hasLength(1));
      await expectLater(
        provider.search('🚗' * 101),
        throwsA(apiError('invalid_offer_search')),
      );
    },
  );
  test(
    'token concurrente, vencimiento y 401 tardío '
    'no generan emisiones duplicadas',
    () async {
      var now = DateTime.utc(2026);
      var calls = 0;
      final gate = Completer<void>();
      final client = MockClient((r) async {
        calls++;
        if (calls == 1) await gate.future;
        return json({'access_token': 'access-$calls', 'expires_in': 7200});
      });
      addTearDown(client.close);
      final tokens = EbayTokens(config, client, clock: () => now);
      final a = tokens.accessToken();
      final b = tokens.accessToken();
      gate.complete();
      expect(await Future.wait([a, b]), ['access-1', 'access-1']);
      expect(calls, 1);
      expect(await tokens.accessToken(), 'access-1');
      now = now.add(const Duration(hours: 2));
      expect(await tokens.accessToken(), 'access-2');
      expect(calls, 2);
      expect(await tokens.accessToken(rejectedToken: 'access-1'), 'access-2');
      expect(calls, 2);
    },
  );
  test('Production utiliza su host y sólo enlaces del entorno real', () async {
    const production = EbayConfig(
      clientId: 'qa-id',
      clientSecret: 'qa-secret',
      environment: 'production',
    );
    final client = MockClient((r) async {
      expect(r.url.host, 'api.ebay.com');
      return r.url.path.endsWith('/token')
          ? json({'access_token': 'qa-access', 'expires_in': 7200})
          : json({
              'total': 1,
              'itemSummaries': [
                {
                  ...item,
                  'itemWebUrl': 'https://www.ebay.com/itm/110590963673',
                },
              ],
            });
    });
    addTearDown(client.close);
    final result = (await EbayProvider(
      EbayTokens(production, client),
      client,
    ).search('spark plug')).single;
    expect(result.environment, 'production');
    expect(
      EbayProvider.safeUrl(
        Uri.parse(item['itemWebUrl']! as String),
        'production',
      ),
      isFalse,
    );
  });
  test(
    '401 renueva una sola vez; un segundo rechazo termina la petición',
    () async {
      for (final accepted in [true, false]) {
        var tokenCalls = 0;
        var searchCalls = 0;
        final client = MockClient((r) async {
          if (r.url.path.endsWith('/token')) {
            return json({
              'access_token': 'qa-${++tokenCalls}',
              'expires_in': 7200,
            });
          }
          searchCalls++;
          return searchCalls == 1 || !accepted
              ? json({}, 401)
              : json({
                  'total': 1,
                  'itemSummaries': [item],
                });
        });
        final result = EbayProvider(
          EbayTokens(config, client),
          client,
        ).search('spark plug');
        if (accepted) {
          expect(await result, hasLength(1));
        } else {
          await expectLater(
            result,
            throwsA(apiError('ebay_credentials_rejected')),
          );
        }
        expect(tokenCalls, 2);
        expect(searchCalls, 2);
        client.close();
      }
    },
  );
  test(
    'no acepta enlaces falsos, entorno cruzado, IDs ni precios adulterados',
    () async {
      final variants = <Map<String, Object?>>[
        {
          ...item,
          'itemWebUrl': 'https://sandbox.ebay.com.attacker.example/itm/123',
        },
        {...item, 'itemWebUrl': 'https://www.ebay.com/itm/123'},
        {
          ...item,
          'itemWebUrl': 'https://user:password@sandbox.ebay.com/itm/123',
        },
        {...item, 'itemWebUrl': 'https://sandbox.ebay.com:444/itm/123'},
        {...item, 'itemWebUrl': 'https://sandbox.ebay.com/itm/123#fragment'},
        {...item, 'itemWebUrl': 'https://sandbox.ebay.com/signin'},
        {...item, 'itemId': 'MLC12345678'},
        {
          ...item,
          'price': {'value': '-5', 'currency': 'USD'},
        },
        {
          ...item,
          'price': {'value': 5, 'currency': 'USD'},
        },
        {
          ...item,
          'price': {'value': '5.00', 'currency': 'DOLARES'},
        },
        {
          ...item,
          'buyingOptions': ['AUCTION'],
        },
      ];
      for (final bad in variants) {
        final client = MockClient(
          (r) async => r.url.path.endsWith('/token')
              ? json({'access_token': 'qa-access', 'expires_in': 7200})
              : json({
                  'total': 1,
                  'itemSummaries': [bad],
                }),
        );
        await expectLater(
          EbayProvider(EbayTokens(config, client), client).search('spark plug'),
          throwsA(apiError('provider_invalid_response')),
        );
        client.close();
      }
    },
  );
  test('403, límite y error remoto conservan códigos del proveedor', () async {
    for (final pair in {
      403: 'provider_access_denied',
      429: 'provider_rate_limited',
      500: 'provider_unavailable',
    }.entries) {
      final client = MockClient(
        (r) async => r.url.path.endsWith('/token')
            ? json({'access_token': 'qa-access', 'expires_in': 7200})
            : json({'secret': 'do-not-expose'}, pair.key),
      );
      await expectLater(
        EbayProvider(EbayTokens(config, client), client).search('spark plug'),
        throwsA(apiError(pair.value)),
      );
      client.close();
    }
  });
  test(
    'respuesta vacía válida, IDs duplicados y cuerpos malformados',
    () async {
      for (final data in <Object?>[
        {'total': 0},
        {
          'total': 2,
          'itemSummaries': [item, item],
        },
      ]) {
        final client = MockClient(
          (r) async => r.url.path.endsWith('/token')
              ? json({'access_token': 'qa-access', 'expires_in': 7200})
              : json(data),
        );
        final result = await EbayProvider(
          EbayTokens(config, client),
          client,
        ).search('spark plug');
        expect(result, hasLength((data! as Map)['total'] == 0 ? 0 : 1));
        client.close();
      }
      for (final data in <Object?>[
        {'total': 1},
        {'total': 0, 'itemSummaries': <String, Object?>{}},
        [],
        {'total': '1'},
        null,
      ]) {
        final client = MockClient(
          (r) async => r.url.path.endsWith('/token')
              ? json({'access_token': 'qa-access', 'expires_in': 7200})
              : json(data),
        );
        await expectLater(
          EbayProvider(EbayTokens(config, client), client).search('spark plug'),
          throwsA(apiError('provider_invalid_response')),
        );
        client.close();
      }
    },
  );
  test(
    'credenciales faltantes, rechazadas y token inválido no exponen secretos',
    () async {
      final client = MockClient(
        (r) async => json({'error_description': 'private'}, 401),
      );
      await expectLater(
        EbayTokens(const EbayConfig(), client).accessToken(),
        throwsA(apiError('ebay_not_configured')),
      );
      await expectLater(
        EbayTokens(config, client).accessToken(),
        throwsA(apiError('ebay_credentials_rejected')),
      );
      client.close();
      final malformed = MockClient(
        (r) async => json({'access_token': '', 'expires_in': 7200}),
      );
      await expectLater(
        EbayTokens(config, malformed).accessToken(),
        throwsA(apiError('provider_invalid_response')),
      );
      malformed.close();
      expect(
        () => const EbayConfig(environment: 'invalid').apiHost,
        throwsFormatException,
      );
    },
  );
  test(
    'transporte acota cuerpo, desactiva redirecciones y traduce caída de red',
    () async {
      final large = MockClient((r) async {
        expect(r.followRedirects, isFalse);
        return http.Response('x' * (1024 * 1024 + 1), 200);
      });
      await expectLater(
        providerRequest(
          large,
          'GET',
          Uri.https('api.sandbox.ebay.com', '/test'),
        ),
        throwsA(apiError('provider_invalid_response')),
      );
      large.close();
      final offline = MockClient(
        (r) async => throw const SocketException('offline'),
      );
      await expectLater(
        providerRequest(
          offline,
          'GET',
          Uri.https('api.sandbox.ebay.com', '/test'),
        ),
        throwsA(apiError('provider_unavailable')),
      );
      offline.close();
    },
  );
  test(
    'recibo eBay conserva proveedor, entorno y pertenencia a usuario/taller',
    () async {
      final client = MockClient(
        (r) async => r.url.path.endsWith('/token')
            ? json({'access_token': 'qa-access', 'expires_in': 7200})
            : json({
                'total': 1,
                'itemSummaries': [item],
              }),
      );
      addTearDown(client.close);
      final service = OfferService(
        EbayProvider(EbayTokens(config, client), client),
      );
      const identity = AuthIdentity(
        userId: 1,
        workshopId: 1,
        userPublicId: 'u',
        workshopPublicId: 'w',
        role: UserRole.mecanico,
        name: 'QA',
      );
      final result = await service.search(
        identity,
        const OfferSearchPlan(
          code: 'P0301',
          componentId: 'c',
          componentName: 'Bujía',
          query: 'Bujía',
        ),
        providerId: 'ebay',
      );
      expect(result['environment'], 'sandbox');
      expect(result['query'], 'spark plug');
      final row = (result['items']! as List).single as Map;
      final receipt = service.receipt(row['offer_token'] as String, identity);
      expect(receipt.offer.provider, 'ebay');
      expect(receipt.offer.environment, 'sandbox');
      expect(
        () => service.receipt(
          row['offer_token'] as String,
          const AuthIdentity(
            userId: 2,
            workshopId: 1,
            userPublicId: 'u2',
            workshopPublicId: 'w',
            role: UserRole.mecanico,
            name: 'QA2',
          ),
        ),
        throwsA(apiError('offer_expired')),
      );
    },
  );
}
