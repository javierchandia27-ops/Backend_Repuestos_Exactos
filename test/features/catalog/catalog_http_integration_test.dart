import 'dart:convert';
import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/config/database_config.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/http/request_metadata.dart';
import 'package:test/test.dart';

void main() {
  test(
    'catalog applies compatibility, tenant pricing and VIN permissions',
    () async {
      final env = DotEnv()..load([Platform.environment['RE_DB_ENV_FILE']!]);
      final base = Platform.environment['TEST_API_URL']!;
      final client = HttpClient();
      addTearDown(client.close);
      final database = Database(DatabaseConfig.load());
      addTearDown(database.close);
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

      Future<Map<String, dynamic>> get(String path, String token) async {
        final response = await send('GET', path, token: token);
        expect(response.status, 200, reason: path);
        return response.body;
      }

      try {
        expect((await send('GET', '/catalog/brands')).status, 401);
        final first = await login('admin@losaromos.example');
        final second = await login('admin@nuble.example');
        final mechanic = await login('mecanico1@losaromos.example');
        final auditor = await login('auditor@losaromos.example');
        final brands = (await get('/catalog/brands', first))['data'] as List;
        expect(brands, isNotEmpty);
        for (final token in [second, mechanic, auditor]) {
          expect((await get('/catalog/brands', token))['data'], brands);
        }
        final toyota = brands.cast<Map<String, dynamic>>().firstWhere(
          (item) => item['nombre'] == 'Toyota',
        );
        final models =
            (await get(
                  '/catalog/brands/${toyota['id_publico']}/models',
                  first,
                ))['data']
                as List;
        final yaris = models.cast<Map<String, dynamic>>().firstWhere(
          (item) => item['nombre'] == 'Yaris',
        );
        final codes = await get('/catalog/dtc?q=p03&limit=2', first);
        expect(codes['has_more'], isTrue);
        expect(
          (codes['data'] as List).every(
            (item) => (item as Map<String, dynamic>)['codigo']
                .toString()
                .startsWith('P03'),
          ),
          isTrue,
        );
        final all =
            (await get('/catalog/dtc/P0300/parts?limit=100', first))['data']
                as List;
        expect(all, isNotEmpty);
        final ids = <Object?>[];
        int? offset = 0;
        var pages = 0;
        while (offset != null) {
          final page = await get(
            '/catalog/dtc/P0300/parts?limit=2&offset=$offset',
            first,
          );
          ids.addAll(
            (page['data'] as List).map(
              (item) => (item as Map<String, dynamic>)['id_publico'],
            ),
          );
          offset = page['next_offset'] as int?;
          expect(++pages, lessThan(100));
        }
        expect(
          ids,
          all
              .map((item) => (item as Map<String, dynamic>)['id_publico'])
              .toList(),
        );
        expect(ids.toSet().length, ids.length);
        final compatible =
            (await get(
                  '/catalog/dtc/P0300/parts?model=${yaris['id_publico']}&year=2018&limit=100',
                  first,
                ))['data']
                as List;
        expect(compatible, isNotEmpty);
        expect(compatible.length, lessThan(all.length));
        expect(
          (await get(
            '/catalog/dtc/P0300/parts?model=${yaris['id_publico']}&year=1981',
            first,
          ))['data'],
          isEmpty,
        );
        final other =
            (await get('/catalog/dtc/P0300/parts?limit=100', second))['data']
                as List;
        final otherById = {
          for (final row in other.cast<Map<String, dynamic>>())
            row['id_publico']: row,
        };
        expect(otherById.keys.toSet(), ids.toSet());
        expect(
          all.cast<Map<String, dynamic>>().any(
            (row) =>
                row['precio_venta'] !=
                otherById[row['id_publico']]!['precio_venta'],
          ),
          isTrue,
        );
        for (final row in all.cast<Map<String, dynamic>>()) {
          expect(row['precio_venta'], matches(r'^[0-9]+$'));
          expect(row.containsKey('precio_referencia'), isFalse);
          expect(row.containsKey('id'), isFalse);
        }
        for (final token in [mechanic, auditor]) {
          expect(
            (await get('/catalog/dtc/P0300/parts?limit=100', token))['data'],
            all,
          );
        }
        final metadata = RequestMetadata.create(ip: '127.0.0.1');
        final identity = (await database.authenticate(
          'admin@losaromos.example',
          env['CLAVE_DEMO']!,
          metadata: metadata,
        ))!;
        final otherIdentity = (await database.authenticate(
          'admin@nuble.example',
          env['CLAVE_DEMO']!,
          metadata: metadata,
        ))!;
        Future<List<Map<String, dynamic>>> vehicles(
          AuthIdentity user,
        ) => database.withUserTransaction(
          user,
          metadata: metadata,
          action: (tx) async => (await tx.execute(
            'SELECT id_publico, vin FROM public.vehiculo '
            'WHERE vin IS NOT NULL ORDER BY id',
          )).map((row) => row.toColumnMap()).toList(),
        );
        final ownVehicles = await vehicles(identity);
        final otherVehicles = await vehicles(otherIdentity);
        final foreignVins = otherVehicles.map((v) => v['vin']).toSet();
        final own = ownVehicles.firstWhere(
          (v) => !foreignVins.contains(v['vin']),
        );
        final vin = own['vin'] as String;
        final found = await get('/search?vin=${vin.toLowerCase()}', first);
        expect(
          (found['data'] as Map<String, dynamic>)['id_publico'],
          own['id_publico'],
        );
        expect(
          (found['data'] as Map<String, dynamic>).containsKey('titular_nombre'),
          isFalse,
        );
        expect((await get('/search?vin=$vin', second))['data'], isNull);
        expect(
          (await send('GET', '/search?vin=$vin', token: auditor)).status,
          403,
        );
        final restricted = <String>[];
        for (final vehicle in ownVehicles) {
          final result = await get('/search?vin=${vehicle['vin']}', mechanic);
          if (result['data'] == null) {
            restricted.add(vehicle['vin'] as String);
          }
        }
        expect(restricted, isNotEmpty);
        for (final path in [
          '/catalog/dtc?q=P0%25',
          '/catalog/dtc?q=P0300&q=P0301',
          '/catalog/dtc/P0300/parts?year=2018',
          '/catalog/dtc/P0300/parts?taller_id=2',
          '/catalog/brands/bad/models',
          '/search?vin=bad',
          '/search?vin=$vin&rol=admin',
        ]) {
          expect(
            (await send('GET', path, token: first)).status,
            400,
            reason: path,
          );
        }
        expect(
          (await send('GET', '/catalog/dtc/P3999/parts', token: first)).status,
          404,
        );
        expect(
          (await send('POST', '/catalog/brands', token: first)).status,
          405,
        );
        expect(await database.checkConnection(), isTrue);
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
