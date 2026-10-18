import 'dart:io';

import 'package:re_api/config/database_config.dart';
import 'package:re_api/database/database.dart';

Future<void> main() async {
  final database = Database(DatabaseConfig.load());
  try {
    if (!await database.checkConnection()) {
      stderr.writeln(
        'No se confirmó el rol de aplicación o las tablas esperadas.',
      );
      exitCode = 1;
      return;
    }
    final tables = await database.listTables();
    final tableCount = tables.length;
    stdout
      ..writeln('PostgreSQL conectado con app_backend_user.')
      ..writeln('Tablas de public: $tableCount');
    for (final table in tables) {
      stdout.writeln('- $table');
    }
  } on Exception catch (_) {
    stderr.writeln(
      'No fue posible consultar PostgreSQL. Revisar Docker y DB_* en .env.',
    );
    exitCode = 1;
  } finally {
    await database.close();
  }
}
