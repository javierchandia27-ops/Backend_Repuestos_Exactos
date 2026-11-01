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
    'vehículo modificado después de buscar devuelve conflicto de contexto',
    () async {
      final env = DotEnv()..load([Platform.environment['RE_DB_ENV_FILE']!]);
      final db = Database(DatabaseConfig.load());
      addTearDown(db.close);
      final metadata = RequestMetadata.create(ip: '127.0.0.1');
      final identity = (await db.authenticate(
        'admin@losaromos.example',
        env['CLAVE_DEMO']!,
        metadata: metadata,
      ))!;
      await expectLater(
        db.withUserTransaction<void>(
          identity,
          metadata: metadata,
          action: (tx) async {
            final vehicle = (await tx.execute('''
        SELECT v.id_publico,mo.id_publico,v.anio FROM public.vehiculo v
        JOIN public.modelo_vehiculo mo ON mo.id=v.modelo_vehiculo_id ORDER BY v.id LIMIT 1
      ''')).single;
            final plans = OfferPlanRepository(tx);
            final component = (await plans.components('P0301')).first;
            final plan = await plans.plan(
              OfferSearchRequest(
                code: 'P0301',
                componentId: component['id']! as String,
                modelId: vehicle[1]! as String,
                year: vehicle[2]! as int,
                vehicleId: vehicle[0]! as String,
              ),
            );
            await tx.execute(
              Sql.named(
                'UPDATE public.vehiculo SET anio=anio+1 '
                'WHERE id_publico=@id::uuid',
              ),
              parameters: {'id': vehicle[0]},
            );
            final receipt = OfferReceipt(
              offer: Offer(
                id: 'MLC12345678',
                title: 'Sólo prueba transaccional',
                price: null,
                currency: null,
                url: null,
                kind: 'catalog_product',
                catalogStatus: 'inactive',
                queriedAt: DateTime.now().toUtc(),
              ),
              plan: plan,
              userId: identity.userId,
              workshopId: identity.workshopId,
              expiresAt: DateTime.now().toUtc().add(
                const Duration(minutes: 10),
              ),
            );
            await expectLater(
              SavedPartsRepository(tx).save(
                const SavePartRequest(
                  token: 'test-context',
                  key: '601531d7-086a-40f4-83dc-8c180ca64c78',
                  note: '',
                ),
                receipt,
                identity,
              ),
              throwsA(
                isA<ApiError>()
                    .having((e) => e.statusCode, 'status', 409)
                    .having((e) => e.code, 'code', 'invalid_saved_context'),
              ),
            );
            throw _Rollback();
          },
        ),
        throwsA(isA<_Rollback>()),
      );
    },
    skip:
        Platform.environment['RUN_DATABASE_TESTS'] != 'true' ||
        Platform.environment['RE_DB_ENV_FILE'] == null,
  );
}
