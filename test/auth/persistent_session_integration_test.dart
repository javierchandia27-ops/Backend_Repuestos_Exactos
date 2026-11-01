import 'dart:convert';
import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/config/database_config.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/request_metadata.dart';
import 'package:test/test.dart';

void main() {
  final enabled =
      Platform.environment['RUN_DATABASE_TESTS'] == 'true' &&
      Platform.environment['RE_DB_ENV_FILE'] != null;
  test(
    'familia persistente sobrevive otra instancia y logout revoca la rotación',
    () async {
      expect(
        Platform.environment['DB_NAME']?.startsWith('re_api_preflight_'),
        isTrue,
      );
      final secrets = DotEnv()..load([Platform.environment['RE_DB_ENV_FILE']!]);
      final db = Database(DatabaseConfig.load());
      addTearDown(db.close);
      final identity = (await db.authenticate(
        'admin@losaromos.example',
        secrets['CLAVE_DEMO']!,
        metadata: RequestMetadata.create(),
      ))!;
      final first = await SessionStore(database: db).create(identity);
      final recreated = SessionStore(database: db);
      expect(
        (await recreated.find(first.token))?.identity.userId,
        identity.userId,
      );
      final second = (await recreated.renew(first.refreshToken!))!;
      expect(second.token == first.token, isFalse);
      expect(second.refreshToken == first.refreshToken, isFalse);
      expect(await recreated.find(first.token), isNull);
      expect(
        (await recreated.find(second.token))?.identity.workshopId,
        identity.workshopId,
      );
      await expectLater(
        recreated.renew(first.refreshToken!),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'status', 409)),
      );
      await recreated.invalidate(refresh: second.refreshToken);
      expect(await recreated.find(second.token), isNull);
      expect(await recreated.renew(first.refreshToken!), isNull);
    },
    skip: !enabled,
  );

  test(
    'HTTP cookie HttpOnly, CORS/CSRF, rotación concurrente y cierre con acceso inválido',
    () async {
      expect(
        Platform.environment['DB_NAME']?.startsWith('re_api_preflight_'),
        isTrue,
      );
      final secrets = DotEnv()..load([Platform.environment['RE_DB_ENV_FILE']!]);
      final client = http.Client();
      addTearDown(client.close);
      final base = Platform.environment['TEST_API_URL']!;
      Future<http.Response> post(
        String path, {
        String? cookie,
        String? bearer,
        bool sessionHeader = true,
        String origin = 'http://localhost:8080',
        Map<String, Object?>? body,
      }) => client.post(
        Uri.parse('$base$path'),
        headers: {
          'origin': origin,
          'content-type': 'application/json',
          if (sessionHeader) 'x-re-session': '1',
          if (cookie != null) 'cookie': cookie,
          if (bearer != null) 'authorization': 'Bearer $bearer',
        },
        body: body == null ? null : jsonEncode(body),
      );
      Future<http.Response> login() => post(
        '/auth/login',
        body: {
          'email': 'admin@losaromos.example',
          'password': secrets['CLAVE_DEMO'],
        },
      );
      String cookieOf(http.Response r) =>
          r.headers['set-cookie']!.split(';').first;
      String accessOf(http.Response r) =>
          (jsonDecode(r.body) as Map)['access_token'] as String;
      final initial = await login();
      expect(initial.statusCode, 200);
      final flags = initial.headers['set-cookie']!;
      expect(flags.contains('HttpOnly'), isTrue);
      expect(flags.contains('SameSite=Strict'), isTrue);
      expect(flags.contains('Path=/auth'), isTrue);
      expect(initial.headers['access-control-allow-credentials'], 'true');
      expect(
        (jsonDecode(initial.body) as Map).containsKey('refresh_token'),
        isFalse,
      );
      final cookie = cookieOf(initial);
      expect(
        (await post(
          '/auth/refresh',
          cookie: cookie,
          sessionHeader: false,
        )).statusCode,
        403,
      );
      expect(
        (await post(
          '/auth/refresh',
          cookie: cookie,
          origin: 'https://evil.invalid',
        )).statusCode,
        403,
      );
      final concurrent = await Future.wait([
        post('/auth/refresh', cookie: cookie),
        post('/auth/refresh', cookie: cookie),
      ]);
      expect(concurrent.map((r) => r.statusCode).toSet(), {200, 409});
      final fresh = concurrent.singleWhere((r) => r.statusCode == 200);
      expect(
        concurrent
            .singleWhere((r) => r.statusCode == 409)
            .headers
            .containsKey('set-cookie'),
        isFalse,
      );
      final nextCookie = cookieOf(fresh);
      final nextAccess = accessOf(fresh);
      expect(nextCookie == cookie, isFalse);
      expect(
        (await client.get(
          Uri.parse('$base/auth/me'),
          headers: {'authorization': 'Bearer ${accessOf(initial)}'},
        )).statusCode,
        401,
      );
      expect(
        (await client.get(
          Uri.parse('$base/auth/me'),
          headers: {'authorization': 'Bearer $nextAccess'},
        )).statusCode,
        200,
      );
      final closed = await post(
        '/auth/logout',
        cookie: nextCookie,
        bearer: accessOf(initial),
      );
      expect(closed.statusCode, 204);
      expect(closed.headers['set-cookie']!.contains('Max-Age=0'), isTrue);
      expect(
        (await client.get(
          Uri.parse('$base/auth/me'),
          headers: {'authorization': 'Bearer $nextAccess'},
        )).statusCode,
        401,
      );
      expect((await post('/auth/refresh', cookie: nextCookie)).statusCode, 401);
      expect((await post('/auth/logout')).statusCode, 204);
    },
    skip: !enabled || Platform.environment['TEST_API_URL'] == null,
  );
}
