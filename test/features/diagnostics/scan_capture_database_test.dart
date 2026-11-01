import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/config/database_config.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/features/diagnostics/dto/create_scan_request.dart';
import 'package:re_api/features/diagnostics/repositories/diagnostic_capture_repository.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/request_metadata.dart';
import 'package:test/test.dart';

class _Rollback implements Exception {}

void main() {
  test(
    'captura OBD conserva desconocidos, categorías y reintentos bajo RLS',
    () async {
      final env = DotEnv()..load([Platform.environment['RE_DB_ENV_FILE']!]);
      final db = Database(DatabaseConfig.load());
      addTearDown(db.close);
      final meta = RequestMetadata.create(ip: '127.0.0.1');
      for (final email in [
        'admin@losaromos.example',
        'mecanico1@losaromos.example',
      ]) {
        final user = (await db.authenticate(
          email,
          env['CLAVE_DEMO']!,
          metadata: meta,
        ))!;
        await expectLater(
          db.withUserTransaction<void>(
            user,
            metadata: meta,
            action: (tx) async {
              final repository = DiagnosticCaptureRepository(tx);
              final vehicles = await repository.vehicles();
              final devices = await repository.devices();
              expect(vehicles, isNotEmpty);
              expect(devices, isNotEmpty);
              final input = CreateScanRequest.parse({
                'vehicle_id': vehicles.first['id'],
                'device_id': devices.first['id'],
                'kilometraje': 12345,
                'idempotency_key': '27c43803-8f53-4e9d-a974-87bb01b8d754',
                'captured_at': DateTime.now().toUtc().toIso8601String(),
                'protocol': 'ELM protocolo 6',
                'services': {'03': 'ok', '07': 'ok', '0A': 'no_data'},
                'observations': [
                  {'code': 'P0301', 'ecu': '7E8', 'kind': 'stored'},
                  {'code': 'P3999', 'ecu': '7E8', 'kind': 'stored'},
                  {'code': 'P0301', 'ecu': '7E9', 'kind': 'pending'},
                ],
              });
              final id = await repository.create(input, user);
              expect(await repository.create(input, user), id);
              final detail = await repository.detail(id);
              final observations = (detail['observations']! as List)
                  .cast<Map<String, dynamic>>();
              expect(observations.length, 3);
              expect(
                observations.firstWhere(
                  (o) => o['code'] == 'P3999',
                )['description'],
                isNull,
              );
              final counts = await tx.execute(
                Sql.named('''
SELECT s.estado::text,
          (SELECT count(*) FROM public.falla_sesion f WHERE f.sesion_id=s.id),
          (SELECT count(*) FROM public.cotizacion c WHERE c.sesion_id=s.id)
          FROM public.sesion_diagnostico s WHERE s.id_publico=@id::uuid'''),
                parameters: {'id': id},
              );
              expect(counts.single.toList(), ['pendiente', 1, 0]);
              final forged = CreateScanRequest.parse({
                'vehicle_id': vehicles.first['id'],
                'device_id': devices.first['id'],
                'kilometraje': 12346,
                'idempotency_key': input.key,
                'captured_at': input.capturedAt.toIso8601String(),
                'protocol': input.protocol,
                'services': input.services,
                'observations': input.observations,
              });
              await expectLater(
                repository.create(forged, user),
                throwsA(
                  isA<ApiError>().having(
                    (e) => e.code,
                    'code',
                    'idempotency_conflict',
                  ),
                ),
              );
              final workshop = user.workshopId.toString();
              await tx.execute(
                "SELECT set_config('app.taller_id','99999999',true)",
              );
              await expectLater(
                repository.detail(id),
                throwsA(
                  isA<ApiError>().having((e) => e.statusCode, 'status', 404),
                ),
              );
              await tx.execute(
                Sql.named("SELECT set_config('app.taller_id',@id,true)"),
                parameters: {'id': workshop},
              );
              if (user.role.name == 'propietario') {
                final device = await repository.registerDevice(
                  'vLinker MC',
                  'c0a43803-8f53-4e9d-a974-87bb01b8d754',
                );
                expect(
                  (await repository.registerDevice(
                    'vLinker MC',
                    'c0a43803-8f53-4e9d-a974-87bb01b8d754',
                  ))['id'],
                  device['id'],
                );
              }
              throw _Rollback();
            },
          ),
          throwsA(isA<_Rollback>()),
        );
      }
    },
    skip:
        Platform.environment['RUN_DATABASE_TESTS'] != 'true' ||
        Platform.environment['RE_DB_ENV_FILE'] == null,
  );
}
