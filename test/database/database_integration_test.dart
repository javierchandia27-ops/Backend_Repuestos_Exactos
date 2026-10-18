import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:re_api/config/database_config.dart';
import 'package:re_api/database/database.dart';
import 'package:test/test.dart';

void main() {
  test(
    'real database: schema, restricted access and transaction role cleanup',
    () async {
      final config = DatabaseConfig.load();
      final database = Database(config);
      addTearDown(database.close);
      expect(await database.checkConnection(), isTrue);
      expect(
        await database.listTables(),
        containsAll([
          'vehiculo',
          'sesion_diagnostico',
          'cotizacion',
        ]),
      );

      final connection = await Connection.open(
        config.endpoint,
        settings: ConnectionSettings(
          sslMode: config.sslMode,
          connectTimeout: const Duration(seconds: 5),
          queryTimeout: const Duration(seconds: 5),
        ),
      );
      addTearDown(connection.close);
      // Sin rol, no debe ser posible leer tablas operativas.
      await expectLater(
        connection.execute('SELECT id FROM public.vehiculo LIMIT 1'),
        throwsA(
          isA<ServerException>().having(
            (error) => error.code,
            'SQLSTATE',
            '42501',
          ),
        ),
      );

      // Lectura de catálogo global, sin datos personales ni cambios.
      final count = await connection.runTx((session) async {
        await session.execute('SET LOCAL ROLE taller_auditor');
        final rows = await session.execute(
          'SELECT count(*) FROM public.marca_vehiculo',
        );
        return rows.single[0]! as int;
      });
      expect(count, greaterThanOrEqualTo(0));
      final roleAfterCommit = await connection.execute('SELECT current_user');
      expect(roleAfterCommit.single[0], 'app_backend_user');

      await expectLater(
        connection.runTx<void>((session) async {
          await session.execute('SET LOCAL ROLE taller_auditor');
          throw const FormatException('intentional rollback');
        }),
        throwsFormatException,
      );
      final roleAfterRollback = await connection.execute('SELECT current_user');
      expect(roleAfterRollback.single[0], 'app_backend_user');
    },
    skip: Platform.environment['RUN_DATABASE_TESTS'] != 'true',
  );
}
