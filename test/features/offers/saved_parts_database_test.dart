import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/config/database_config.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/features/offers/dto/offer_search_request.dart';
import 'package:re_api/features/offers/models/offer.dart';
import 'package:re_api/features/offers/models/offer_receipt.dart';
import 'package:re_api/features/offers/repositories/offer_plan_repository.dart';
import 'package:re_api/features/saved_parts/dto/save_part_request.dart';
import 'package:re_api/features/saved_parts/repositories/saved_parts_repository.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/request_metadata.dart';
import 'package:test/test.dart';

class _Rollback implements Exception {}

void main() {
  test(
    'propietario y mecánico guardan; idempotencia, auditoría '
    'y RLS sin residuos',
    () async {
      final env = DotEnv()..load([Platform.environment['RE_DB_ENV_FILE']!]);
      final db = Database(DatabaseConfig.load());
      addTearDown(db.close);
      final metadata = RequestMetadata.create(ip: '127.0.0.1');
      for (final email in [
        'admin@losaromos.example',
        'mecanico1@losaromos.example',
      ]) {
        final identity = (await db.authenticate(
          email,
          env['CLAVE_DEMO']!,
          metadata: metadata,
        ))!;
        await expectLater(
          db.withUserTransaction<void>(
            identity,
            metadata: metadata,
            action: (tx) async {
              final components = await OfferPlanRepository(
                tx,
              ).components('P0301');
              final plan = await OfferPlanRepository(tx).plan(
                OfferSearchRequest(
                  code: 'P0301',
                  componentId: components.first['id']! as String,
                ),
              );
              final now = DateTime.now().toUtc();
              final receipt = OfferReceipt(
                offer: Offer(
                  id: 'MLC12345678',
                  title: 'SOLO PRUEBA ROLLBACK',
                  price: null,
                  currency: null,
                  url: null,
                  kind: 'catalog_product',
                  catalogStatus: 'inactive',
                  queriedAt: now,
                ),
                plan: plan,
                userId: identity.userId,
                workshopId: identity.workshopId,
                expiresAt: now.add(const Duration(minutes: 10)),
              );
              const input = SavePartRequest(
                token: 'test-offer',
                key: '731d03f4-c2e6-4ebf-8dc3-14291e0e8308',
                note: 'Validación transaccional, no es un producto real',
              );
              final repository = SavedPartsRepository(tx);
              final first = await repository.save(input, receipt, identity);
              final retry = await repository.retry(input, identity);
              expect(retry!['id'], first['id']);
              expect(first['kind'], 'catalog_product');
              expect(first['url'], isNull);
              expect(first.containsKey('price'), isFalse);
              expect(first.containsKey('title'), isFalse);
              expect(first['dtc'], 'P0301');
              await expectLater(
                repository.retry(
                  const SavePartRequest(
                    token: 'test-offer',
                    key: '731d03f4-c2e6-4ebf-8dc3-14291e0e8308',
                    note: 'Cambio',
                  ),
                  identity,
                ),
                throwsA(
                  isA<ApiError>().having(
                    (e) => e.code,
                    'code',
                    'idempotency_conflict',
                  ),
                ),
              );
              if (identity.role.name == 'propietario') {
                final audit = await tx.execute(
                  Sql.named('''
          SELECT count(*) FROM public.auditoria_operacion a
          JOIN public.repuesto_guardado g ON g.id=a.registro_id
          WHERE a.tabla='repuesto_guardado' AND g.id_publico=@id::uuid
        '''),
                  parameters: {'id': first['id']},
                );
                expect(audit.single[0], 1);
              }
              final other = await tx.execute(
                'SELECT id FROM public.taller WHERE '
                'id<>public.fn_contexto_taller_id()',
              );
              expect(other, isEmpty);
              await tx.execute(
                "SELECT set_config('app.taller_id','99999999',true)",
              );
              expect(
                (await repository.list(limit: 20, offset: 0))['items'],
                isEmpty,
              );
              await tx.execute(
                Sql.named("SELECT set_config('app.taller_id',@id,true)"),
                parameters: {'id': identity.workshopId.toString()},
              );
              await tx.execute('SAVEPOINT reject_forged_author');
              await expectLater(
                tx.execute(
                  Sql.named('''
          INSERT INTO public.repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,proveedor,id_externo,tipo_referencia,clave_idempotencia,hash_solicitud)
          SELECT taller_id,usuario_id+999999,dtc_id,componente_id,proveedor,id_externo,tipo_referencia,gen_random_uuid(),hash_solicitud
          FROM public.repuesto_guardado WHERE id_publico=@id::uuid
        '''),
                  parameters: {'id': first['id']},
                ),
                throwsA(isA<ServerException>()),
              );
              await tx.execute('ROLLBACK TO SAVEPOINT reject_forged_author');
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
