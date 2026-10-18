import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/config/database_config.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/http/request_metadata.dart';
import 'package:test/test.dart';

void main() {
  test(
    'login, all roles, tenant isolation and pool cleanup against PostgreSQL',
    () async {
      final env = DotEnv()..load([Platform.environment['RE_DB_ENV_FILE']!]);
      final password = env['CLAVE_DEMO']!;
      final database = Database(DatabaseConfig.load(), maxConnectionCount: 1);
      addTearDown(database.close);
      final metadata = RequestMetadata.create(ip: '127.0.0.1');
      final first = (await database.authenticate(
        'admin@losaromos.example',
        password,
        metadata: metadata,
      ))!;
      final second = (await database.authenticate(
        'admin@nuble.example',
        password,
        metadata: metadata,
      ))!;
      expect(first.workshopPublicId != second.workshopPublicId, isTrue);

      expect(
        await database.authenticate(
          'nobody@unknown.example',
          'wrong-password',
          metadata: metadata,
        ),
        isNull,
      );
      expect(
        await database.authenticate(
          'exmecanico@losaromos.example',
          password,
          metadata: metadata,
        ),
        isNull,
      );

      for (final email in [
        'mecanico1@losaromos.example',
        'auditor@losaromos.example',
      ]) {
        final identity = (await database.authenticate(
          email,
          password,
          metadata: metadata,
        ))!;
        await database.withUserTransaction(
          identity,
          metadata: metadata,
          action: (session) async {
            final result = await session.execute(
              'SELECT id_publico FROM public.taller',
            );
            expect(result.single[0], identity.workshopPublicId);
          },
        );
      }

      await Future.wait(
        List.generate(8, (index) {
          final identity = index.isEven ? first : second;
          return database.withUserTransaction(
            identity,
            metadata: metadata,
            action: (session) async {
              final rows = await session.execute(
                'SELECT id_publico FROM public.taller',
              );
              expect(rows.length, 1);
              expect(rows.single[0], identity.workshopPublicId);
              final other = index.isEven ? second : first;
              final crossTenant = await session.execute(
                Sql.named(
                  'SELECT id_publico FROM public.taller '
                  'WHERE id_publico = @id::uuid',
                ),
                parameters: {'id': other.workshopPublicId},
              );
              expect(crossTenant, isEmpty);
            },
          );
        }),
      );

      await expectLater(
        database.withUserTransaction<void>(
          first,
          metadata: metadata,
          action: (_) async {
            throw const FormatException('intentional rollback');
          },
        ),
        throwsFormatException,
      );
      expect(await database.checkConnection(), isTrue);

      final staleRole = AuthIdentity(
        userId: first.userId,
        workshopId: first.workshopId,
        userPublicId: first.userPublicId,
        workshopPublicId: first.workshopPublicId,
        role: UserRole.mecanico,
        name: first.name,
      );
      await expectLater(
        database.withUserTransaction<void>(
          staleRole,
          metadata: metadata,
          action: (_) async => fail('must reject stale role'),
        ),
        throwsA(isA<InvalidSession>()),
      );
      final wrongWorkshop = AuthIdentity(
        userId: first.userId,
        workshopId: second.workshopId,
        userPublicId: first.userPublicId,
        workshopPublicId: second.workshopPublicId,
        role: first.role,
        name: first.name,
      );
      await expectLater(
        database.withUserTransaction<void>(
          wrongWorkshop,
          metadata: metadata,
          action: (_) async => fail('must reject wrong workshop'),
        ),
        throwsA(isA<InvalidSession>()),
      );
      expect(await database.checkConnection(), isTrue);
    },
    skip:
        Platform.environment['RUN_DATABASE_TESTS'] != 'true' ||
        Platform.environment['RE_DB_ENV_FILE'] == null,
  );
}
