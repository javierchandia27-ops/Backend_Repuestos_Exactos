import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:test/test.dart';

void main() {
  test(
    'propietario gestiona equipo y mecánico no se promueve',
    () async {
      final env = DotEnv()..load([Platform.environment['RE_DB_ENV_FILE']!]);
      final client = HttpClient();
      addTearDown(client.close);
      final base = Platform.environment['TEST_API_URL']!;
      final tokens = <String>[];
      Future<({int status, Map<String, dynamic> data})> send(
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
          data: text.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(text) as Map<String, dynamic>,
        );
      }

      Future<String> login(String email, String profile) async {
        final r = await send(
          'POST',
          '/auth/login',
          body: {'email': email, 'password': env['CLAVE_DEMO']},
        );
        expect(r.status, 200);
        expect((r.data['usuario'] as Map)['rol'], profile);
        final token = r.data['access_token'] as String;
        tokens.add(token);
        return token;
      }

      try {
        final owner = await login('admin@losaromos.example', 'propietario');
        final mechanic = await login('mecanico1@losaromos.example', 'mecanico');
        expect((await send('GET', '/invitations', token: owner)).status, 200);
        expect(
          (await send('GET', '/invitations', token: mechanic)).status,
          403,
        );
        expect(
          (await send(
            'POST',
            '/invitations',
            token: mechanic,
            body: {'email': 'unauthorized@gmail.com'},
          )).status,
          403,
        );
        for (final role in ['propietario', 'admin', 'auditor']) {
          final rejected = await send(
            'POST',
            '/invitations',
            token: owner,
            body: {'email': 'forged-role@gmail.com', 'role': role},
          );
          expect(rejected.status, 400);
          expect(rejected.data['error'], 'mechanic_invitation_required');
        }
        final legacy = await send(
          'POST',
          '/auth/login',
          body: {
            'email': 'auditor@losaromos.example',
            'password': env['CLAVE_DEMO'],
          },
        );
        expect(legacy.status, 403);
        expect(legacy.data['error'], 'profile_not_enabled');
        final me = await send('GET', '/auth/me', token: owner);
        expect((me.data['usuario'] as Map)['rol'], 'propietario');
        expect((await send('GET', '/sessions', token: mechanic)).status, 200);
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
