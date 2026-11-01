import 'dart:convert';
import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:test/test.dart';

void main() {
  test(
    'HTTP: buscar, guardar y consultar sin cruzar talleres '
    'ni modificar diagnósticos',
    () async {
      expect(
        Platform.environment['DB_NAME'],
        startsWith('re_api_preflight_'),
        reason: 'La prueba guarda referencias; requiere una base aislada.',
      );
      final env = DotEnv()..load([Platform.environment['RE_DB_ENV_FILE']!]);
      final base = Platform.environment['TEST_API_URL']!;
      final client = HttpClient();
      addTearDown(client.close);
      final tokens = <String>[];
      Future<({int status, Map<String, dynamic> body})> send(
        String method,
        String path, {
        String? token,
        Object? body,
      }) async {
        final request = await client.openUrl(method, Uri.parse(base + path));
        if (token != null) {
          request.headers.set('authorization', 'Bearer $token');
        }
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }
        final response = await request.close();
        final text = await utf8.decoder.bind(response).join();
        return (
          status: response.statusCode,
          body: text.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(text) as Map<String, dynamic>,
        );
      }

      Future<String> login(String email) async {
        final response = await send(
          'POST',
          '/auth/login',
          body: {'email': email, 'password': env['CLAVE_DEMO']},
        );
        expect(response.status, 200);
        final token = response.body['access_token'] as String;
        tokens.add(token);
        return token;
      }

      try {
        for (final path in ['/saved-parts', '/catalog/dtc/P0301/components']) {
          expect((await send('GET', path)).status, 401);
        }
        expect((await send('POST', '/offers/search', body: {})).status, 401);
        expect((await send('POST', '/saved-parts', body: {})).status, 401);
        final owner = await login('admin@losaromos.example');
        final mechanic = await login('mecanico1@losaromos.example');
        final other = await login('admin@nuble.example');
        final historyBefore = await send('GET', '/sessions', token: owner);
        expect(historyBefore.status, 200);
        final components = await send(
          'GET',
          '/catalog/dtc/P0301/components',
          token: owner,
        );
        expect(components.status, 200);
        final component = _items(components.body).first;
        final search = {'dtc': 'P0301', 'component_id': component['id']};
        expect(
          (await send(
            'POST',
            '/offers/search',
            token: owner,
            body: {...search, 'year': 2018},
          )).status,
          400,
        );
        expect(
          (await send(
            'POST',
            '/offers/search',
            token: owner,
            body: {...search, 'taller_id': 1},
          )).status,
          400,
        );
        final found = await send(
          'POST',
          '/offers/search',
          token: owner,
          body: search,
        );
        expect(found.status, 200);
        final items = _items(found.body);
        expect(items, isNotEmpty);
        final offer = items.first;
        expect(offer['kind'], isIn(['listing', 'catalog_product']));
        if (offer['kind'] == 'catalog_product') {
          expect(offer['price'], isNull);
        } else {
          expect(offer['price'], isNotNull);
        }
        expect(offer['compatibility'], 'unverified');
        expect(
          (await send(
            'POST',
            '/offers/search',
            token: owner,
            body: search,
          )).status,
          429,
        );
        final key = _uuid();
        final save = {
          'offer_token': offer['offer_token'],
          'idempotency_key': key,
          'note': 'Validación HTTP en base aislada',
        };
        expect(
          (await send('POST', '/saved-parts', token: other, body: save)).status,
          409,
        );
        expect(
          (await send(
            'POST',
            '/saved-parts',
            token: mechanic,
            body: save,
          )).status,
          409,
        );
        for (final field in ['price', 'usuario_id', 'taller_id', 'url']) {
          expect(
            (await send(
              'POST',
              '/saved-parts',
              token: owner,
              body: {...save, field: 'forjado'},
            )).status,
            400,
          );
        }
        final saved = await send(
          'POST',
          '/saved-parts',
          token: owner,
          body: save,
        );
        expect(saved.status, 200);
        expect(saved.body['dtc'], 'P0301');
        expect(saved.body.containsKey('price'), isFalse);
        expect(saved.body.containsKey('title'), isFalse);
        final retry = await send(
          'POST',
          '/saved-parts',
          token: owner,
          body: save,
        );
        expect(retry.status, 200);
        expect(retry.body['id'], saved.body['id']);
        expect(
          (await send(
            'POST',
            '/saved-parts',
            token: owner,
            body: {...save, 'note': 'Distinta'},
          )).status,
          409,
        );
        final own = await send('GET', '/saved-parts?limit=100', token: owner);
        expect(own.status, 200);
        expect(
          _items(own.body).where((e) => e['id'] == saved.body['id']).length,
          1,
        );
        final coworker = await send(
          'GET',
          '/saved-parts?limit=100',
          token: mechanic,
        );
        expect(
          _items(coworker.body).any(
            (e) => e['id'] == saved.body['id'],
          ),
          isTrue,
        );
        final foreign = await send(
          'GET',
          '/saved-parts?limit=100',
          token: other,
        );
        expect(
          _items(foreign.body).any(
            (e) => e['id'] == saved.body['id'],
          ),
          isFalse,
        );
        final mechanicFound = await send(
          'POST',
          '/offers/search',
          token: mechanic,
          body: search,
        );
        expect(mechanicFound.status, 200);
        final mechanicSaved = await send(
          'POST',
          '/saved-parts',
          token: mechanic,
          body: {
            'offer_token': _items(mechanicFound.body).first['offer_token'],
            'idempotency_key': _uuid(),
            'note': '',
          },
        );
        expect(mechanicSaved.status, 200);
        final page = await send('GET', '/saved-parts?limit=1', token: owner);
        expect(page.status, 200);
        expect(_items(page.body).length, 1);
        expect(page.body['next_offset'], 1);
        final next = await send(
          'GET',
          '/saved-parts?limit=1&offset=1',
          token: owner,
        );
        expect(
          _items(next.body).first['id'],
          isNot(_items(page.body).first['id']),
        );
        for (final path in [
          '/saved-parts?limit=0',
          '/saved-parts?limit=1&limit=2',
          '/saved-parts?taller_id=2',
        ]) {
          expect((await send('GET', path, token: owner)).status, 400);
        }
        expect(
          (await send('DELETE', '/saved-parts', token: owner)).status,
          405,
        );
        final historyAfter = await send('GET', '/sessions', token: owner);
        expect(historyAfter.status, 200);
        expect(historyAfter.body, historyBefore.body);
        expect((await send('POST', '/auth/logout', token: owner)).status, 204);
        expect((await send('GET', '/saved-parts', token: owner)).status, 401);
      } finally {
        for (final token in tokens) {
          await send('POST', '/auth/logout', token: token);
        }
      }
    },
    skip:
        Platform.environment['RUN_OFFERS_HTTP_TESTS'] != 'true' ||
        Platform.environment['TEST_API_URL'] == null ||
        Platform.environment['RE_DB_ENV_FILE'] == null,
  );
}

// UUID de prueba, sin reutilizar claves de ejecuciones anteriores.
String _uuid() {
  // El identificador sólo necesita unicidad en esta prueba, no es un secreto.
  final suffix = DateTime.now().microsecondsSinceEpoch
      .toRadixString(16)
      .padLeft(12, '0');
  return 'c01a0000-0000-4000-8000-${suffix.substring(suffix.length - 12)}';
}

List<Map<String, dynamic>> _items(Map<String, dynamic> body) =>
    (body['items'] as List).cast<Map<String, dynamic>>();
