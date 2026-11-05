import 'dart:convert';
import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test(
    'HTTP eBay: búsqueda, guardado, reintento, historial '
    'y aislamiento del taller',
    () async {
      expect(Platform.environment['DB_NAME'], startsWith('re_api_preflight_'));
      final secrets = DotEnv()..load([Platform.environment['RE_DB_ENV_FILE']!]);
      final client = http.Client();
      addTearDown(client.close);
      final base = Platform.environment['TEST_API_URL']!;
      final tokens = <String>[];
      Future<({int status, Map<String, dynamic> data})> call(
        String method,
        String path, {
        String? token,
        Map<String, Object?>? body,
      }) async {
        final request = http.Request(method, Uri.parse(base + path));
        if (token != null) request.headers['authorization'] = 'Bearer $token';
        if (body != null) {
          request.headers['content-type'] = 'application/json';
          request.body = jsonEncode(body);
        }
        final response = await http.Response.fromStream(
          await client.send(request),
        );
        return (
          status: response.statusCode,
          data: response.body.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      Future<String> login(String email) async {
        final r = await call(
          'POST',
          '/auth/login',
          body: {'email': email, 'password': secrets['CLAVE_DEMO']},
        );
        expect(r.status, 200);
        final token = r.data['access_token'] as String;
        tokens.add(token);
        return token;
      }

      try {
        final own = await login('mecanico2@losaromos.example');
        final other = await login('admin@nuble.example');
        final before = await call('GET', '/sessions', token: own);
        expect(
          (await call(
            'POST',
            '/offers/search',
            body: {'provider': 'ebay'},
          )).status,
          401,
        );
        final components = await call(
          'GET',
          '/catalog/dtc/P0301/components',
          token: own,
        );
        final list = (components.data['items'] as List)
            .cast<Map<String, dynamic>>();
        final component = list.firstWhere(
          (c) => c['name'] == 'Bujía',
          orElse: () => list.first,
        );
        final input = <String, Object?>{
          'dtc': 'P0301',
          'component_id': component['id'],
          'provider': 'ebay',
        };
        expect(
          (await call(
            'POST',
            '/offers/search',
            token: own,
            body: {...input, 'environment': 'production'},
          )).status,
          400,
        );
        final found = await call(
          'POST',
          '/offers/search',
          token: own,
          body: input,
        );
        expect(found.status, 200);
        expect(found.data['provider'], 'ebay');
        expect(found.data['environment'], 'sandbox');
        final first =
            (found.data['items'] as List).first as Map<String, dynamic>;
        expect(first['provider'], 'ebay');
        expect(first['environment'], 'sandbox');
        expect(first['currency'], 'USD');
        expect(first['compatibility'], 'unverified');
        final suffix = DateTime.now().microsecondsSinceEpoch
            .toRadixString(16)
            .padLeft(12, '0');
        final save = <String, Object?>{
          'offer_token': first['offer_token'],
          'idempotency_key':
              'ebaa0000-0000-4000-8000-${suffix.substring(suffix.length - 12)}',
          'note': 'Prueba aislada eBay Sandbox',
        };
        expect(
          (await call('POST', '/saved-parts', token: other, body: save)).status,
          409,
        );
        expect(
          (await call(
            'POST',
            '/saved-parts',
            token: own,
            body: {...save, 'environment': 'production'},
          )).status,
          400,
        );
        final saved = await call(
          'POST',
          '/saved-parts',
          token: own,
          body: save,
        );
        expect(saved.status, 200);
        expect(saved.data['provider'], 'ebay');
        expect(saved.data['environment'], 'sandbox');
        expect(saved.data['external_id'], first['external_id']);
        expect(saved.data.containsKey('price'), isFalse);
        expect(saved.data.containsKey('title'), isFalse);
        final retry = await call(
          'POST',
          '/saved-parts',
          token: own,
          body: save,
        );
        expect(retry.status, 200);
        expect(retry.data['id'], saved.data['id']);
        final ownList = await call('GET', '/saved-parts?limit=100', token: own);
        expect(
          (ownList.data['items'] as List).cast<Map<String, dynamic>>().where(
            (x) => x['id'] == saved.data['id'],
          ),
          hasLength(1),
        );
        final otherList = await call(
          'GET',
          '/saved-parts?limit=100',
          token: other,
        );
        expect(
          (otherList.data['items'] as List).cast<Map<String, dynamic>>().any(
            (x) => x['id'] == saved.data['id'],
          ),
          isFalse,
        );
        expect((await call('GET', '/sessions', token: own)).data, before.data);
      } finally {
        for (final token in tokens) {
          await call('POST', '/auth/logout', token: token);
        }
      }
    },
    skip:
        Platform.environment['RUN_EBAY_HTTP_TESTS'] != 'true' ||
        Platform.environment['TEST_API_URL'] == null ||
        Platform.environment['RE_DB_ENV_FILE'] == null,
  );
}
