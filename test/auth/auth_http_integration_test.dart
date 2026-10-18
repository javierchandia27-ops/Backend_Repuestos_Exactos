import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:test/test.dart';

void main() {
  test(
    'HTTP login, protected context, tenant isolation and logout',
    () async {
      final env = DotEnv()..load([Platform.environment['RE_DB_ENV_FILE']!]);
      final password = env['CLAVE_DEMO']!;
      final base = Platform.environment['TEST_API_URL']!;
      final client = HttpClient();
      addTearDown(client.close);
      final tokens = <String>[];

      Future<({int status, Map<String, dynamic> body, HttpHeaders headers})>
      send(
        String method,
        String path, {
        String? token,
        Object? body,
        String? rawBody,
        Map<String, String> headers = const {},
      }) async {
        final request = await client.openUrl(method, Uri.parse(base + path));
        headers.forEach(request.headers.set);
        if (token != null) {
          request.headers.set('authorization', 'Bearer $token');
        }
        if (body != null || rawBody != null) {
          request.headers.contentType = ContentType.json;
          request.write(rawBody ?? jsonEncode(body));
        }
        final response = await request.close();
        final text = await utf8.decoder.bind(response).join();
        return (
          status: response.statusCode,
          body: text.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(text) as Map<String, dynamic>,
          headers: response.headers,
        );
      }

      Future<Map<String, dynamic>> login(String email) async {
        final result = await send(
          'POST',
          '/auth/login',
          body: {
            'email': email,
            'password': password,
          },
        );
        expect(result.status, 200);
        expect(result.headers.value('cache-control'), 'no-store');
        final token = result.body['access_token']! as String;
        expect(token.length, 43);
        expect(result.body.containsKey('usuario_id'), isFalse);
        expect(result.body.containsKey('taller_id'), isFalse);
        expect(result.body['token_type'], 'Bearer');
        tokens.add(token);
        return result.body;
      }

      try {
        expect((await send('GET', '/settings')).status, 401);
        expect((await send('GET', '/auth/me')).status, 401);
        final bad = await send(
          'POST',
          '/auth/login',
          body: {
            'email': 'missing@unknown.example',
            'password': 'wrong-password',
          },
        );
        expect(bad.status, 401);
        expect(bad.body, {'error': 'invalid_credentials'});
        final inactive = await send(
          'POST',
          '/auth/login',
          body: {
            'email': 'exmecanico@losaromos.example',
            'password': password,
          },
        );
        expect(inactive.status, 401);
        expect(inactive.body, bad.body);
        expect((await send('GET', '/auth/login')).status, 405);
        expect((await send('POST', '/auth/login', rawBody: '{')).status, 400);
        expect(
          (await send(
            'POST',
            '/auth/login',
            body: {
              'email': 'admin@losaromos.example',
              'password': password,
              'taller_id': 999,
              'rol': 'admin',
            },
          )).status,
          400,
        );

        final first = await login(' ADMIN@LOSAROMOS.EXAMPLE ');
        final second = await login('admin@nuble.example');
        final firstToken = first['access_token']! as String;
        final secondToken = second['access_token']! as String;
        final firstWorkshop = (first['taller'] as Map)['id_publico'];
        final secondWorkshop = (second['taller'] as Map)['id_publico'];
        expect(firstWorkshop == secondWorkshop, isFalse);
        final firstSettings = await send('GET', '/settings', token: firstToken);
        final secondSettings = await send(
          'GET',
          '/settings',
          token: secondToken,
        );
        expect(firstSettings.status, 200);
        expect(secondSettings.status, 200);
        expect(firstSettings.body['id_publico'], firstWorkshop);
        expect(secondSettings.body['id_publico'], secondWorkshop);

        final tampered = await send(
          'GET',
          '/settings?taller_id=$secondWorkshop&rol=admin',
          token: firstToken,
          headers: {
            'x-taller-id': secondWorkshop.toString(),
            'x-usuario-id': '999',
            'x-role': 'admin',
          },
        );
        expect(tampered.status, 200);
        expect(tampered.body['id_publico'], firstWorkshop);
        final me = await send('GET', '/auth/me', token: firstToken);
        expect(me.status, 200);
        expect(me.body['taller'], first['taller']);
        expect(me.body['usuario'], first['usuario']);
        final forged = await send(
          'GET',
          '/settings',
          token: List.filled(43, 'A').join(),
        );
        expect(forged.status, 401);

        for (final email in [
          'mecanico1@losaromos.example',
          'auditor@losaromos.example',
        ]) {
          final account = await login(email);
          final settings = await send(
            'GET',
            '/settings',
            token: account['access_token']! as String,
          );
          expect(settings.status, 200);
          expect(settings.body['id_publico'], firstWorkshop);
        }
        expect(
          (await send('POST', '/auth/logout', token: firstToken)).status,
          204,
        );
        expect((await send('GET', '/auth/me', token: firstToken)).status, 401);
        expect((await send('GET', '/settings', token: firstToken)).status, 401);
        expect(
          (await send('GET', '/settings', token: secondToken)).status,
          200,
        );
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
