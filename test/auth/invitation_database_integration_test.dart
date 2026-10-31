import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/config/database_config.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/features/onboarding/repositories/invitation_repository.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/request_metadata.dart';
import 'package:test/test.dart';

class _Rollback implements Exception {}

void main() {
  test(
    'regenerar y revocar; sin hashes expuestos ni residuos',
    () async {
      final env = DotEnv()..load([Platform.environment['RE_DB_ENV_FILE']!]);
      final database = Database(DatabaseConfig.load());
      addTearDown(database.close);
      final metadata = RequestMetadata.create(ip: '127.0.0.1');
      final admin = (await database.authenticate(
        'admin@losaromos.example',
        env['CLAVE_DEMO']!,
        metadata: metadata,
      ))!;
      final email =
          'invitation-${DateTime.now().microsecondsSinceEpoch}@gmail.com';
      await expectLater(
        database.withUserTransaction<void>(
          admin,
          metadata: metadata,
          action: (tx) async {
            final repository = InvitationRepository(tx);
            final first = await repository.create(email);
            final second = await repository.create(email);
            expect(first['invitation_url'], isNot(second['invitation_url']));
            final list = await repository.list();
            expect(
              list.firstWhere(
                (i) => i['id_publico'] == first['id_publico'],
              )['status'],
              'revoked',
            );
            expect(
              list.firstWhere(
                (i) => i['id_publico'] == second['id_publico'],
              )['status'],
              'pending',
            );
            expect(
              list.every(
                (i) =>
                    !i.containsKey('token_hash') &&
                    !i.containsKey('invitation_url'),
              ),
              isTrue,
            );
            expect(
              await repository.revoke(second['id_publico'] as String),
              isTrue,
            );
            expect(
              await repository.revoke(second['id_publico'] as String),
              isFalse,
            );
            await expectLater(
              repository.create('admin@losaromos.example'),
              throwsA(
                isA<ApiError>().having((e) => e.code, 'code', 'already_member'),
              ),
            );
            throw _Rollback();
          },
        ),
        throwsA(isA<_Rollback>()),
      );
      await database.withUserTransaction<void>(
        admin,
        metadata: metadata,
        action: (tx) async {
          final rows = await tx.execute(
            Sql.named(
              'SELECT count(*) FROM public.invitacion_taller '
              'WHERE email=@email',
            ),
            parameters: {'email': email},
          );
          expect(rows.single[0], 0);
        },
      );
    },
    skip:
        Platform.environment['RUN_DATABASE_TESTS'] != 'true' ||
        Platform.environment['RE_DB_ENV_FILE'] == null,
  );
}
