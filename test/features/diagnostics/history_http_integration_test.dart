import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:test/test.dart';

void main() {
  test(
    'history respects tenants, filters, keyset pages and hidden vehicles',
    () async {
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
        final result = await send(
          'POST',
          '/auth/login',
          body: {'email': email, 'password': env['CLAVE_DEMO']},
        );
        expect(result.status, 200);
        final token = result.body['access_token'] as String;
        tokens.add(token);
        return token;
      }

      Future<Map<String, dynamic>> page(
        String token, {
        int limit = 2,
        String? cursor,
        String? status,
      }) async {
        final uri = Uri(
          path: '/sessions',
          queryParameters: {
            'limit': '$limit',
            if (cursor != null) 'cursor': cursor,
            if (status != null) 'status': status,
          },
        );
        final response = await send('GET', uri.toString(), token: token);
        expect(response.status, 200);
        return response.body;
      }

      Future<List<Map<String, dynamic>>> collect(
        String token, {
        String? status,
      }) async {
        final items = <Map<String, dynamic>>[];
        String? cursor;
        var pages = 0;
        do {
          final result = await page(token, cursor: cursor, status: status);
          items.addAll((result['data'] as List).cast<Map<String, dynamic>>());
          cursor = result['next_cursor'] as String?;
          expect(++pages, lessThan(200));
        } while (cursor != null);
        expect(
          items.map((item) => item['id_publico']).toSet().length,
          items.length,
        );
        return items;
      }

      try {
        expect((await send('GET', '/sessions')).status, 401);
        final first = await login('admin@losaromos.example');
        final second = await login('admin@nuble.example');
        final firstRows = await collect(first);
        final secondRows = await collect(second);
        expect(firstRows, isNotEmpty);
        expect(secondRows, isNotEmpty);
        final firstIds = firstRows.map((item) => item['id_publico']).toSet();
        final secondIds = secondRows.map((item) => item['id_publico']).toSet();
        expect(firstIds.intersection(secondIds), isEmpty);
        for (final item in [...firstRows, ...secondRows]) {
          expect(item.keys, isNot(contains('id')));
          expect(item.keys, isNot(contains('taller_id')));
          expect(item['fallas'], isA<int>());
          expect(item['iniciada_en'], endsWith('Z'));
        }
        // Página única y recorrido por clave deben conservar el mismo orden.
        final large = await page(first, limit: 100);
        expect(
          firstRows.take(100).map((item) => item['id_publico']).toList(),
          (large['data'] as List)
              .map((item) => (item as Map)['id_publico'])
              .toList(),
        );
        for (final status in [
          'pendiente',
          'cotizado',
          'completado',
          'cancelado',
        ]) {
          final filtered = await collect(first, status: status);
          expect(
            filtered.map((item) => item['id_publico']).toList(),
            firstRows
                .where((item) => item['estado'] == status)
                .map((item) => item['id_publico'])
                .toList(),
          );
        }
        final firstPage = await page(first);
        final foreignCursor = firstPage['next_cursor'] as String;
        final denied = await send(
          'GET',
          '/sessions?cursor=$foreignCursor',
          token: second,
        );
        expect(denied.status, 400);
        expect(denied.body, {'error': 'invalid_cursor'});
        for (final query in [
          'limit=101',
          'status=invalid',
          'cursor=bad',
          'limit=2&limit=3',
          'taller_id=2',
        ]) {
          expect(
            (await send('GET', '/sessions?$query', token: first)).status,
            400,
          );
        }
        expect((await send('POST', '/sessions', token: first)).status, 405);
        for (final email in [
          'mecanico1@losaromos.example',
          'auditor@losaromos.example',
        ]) {
          final role = await login(email);
          final rows = await collect(role);
          expect(rows.map((item) => item['id_publico']).toSet(), firstIds);
          if (email.startsWith('mecanico')) {
            // El seed incluye vehículos bloqueados: la sesión sigue visible.
            final hidden = rows.where(
              (item) => item['vehiculo_id_publico'] == null,
            );
            expect(hidden, isNotEmpty);
            for (final item in hidden) {
              expect(item['vehiculo_patente'], isNull);
              expect(item['modelo_nombre'], isNull);
            }
          }
        }
      } finally {
        for (final token in tokens) {
          await send('POST', '/auth/logout', token: token);
        }
      }
    },
    skip:
        Platform.environment['TEST_API_URL'] == null ||
        Platform.environment['RE_DB_ENV_FILE'] == null,
  );
}
