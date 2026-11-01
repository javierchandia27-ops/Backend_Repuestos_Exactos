import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/http/request_metadata.dart';

/// SQL de autenticación fijo: sin privilegios operativos ni tokens en claro.
class PersistentSessionRepository {
  /// Comparte el pool de la API.
  PersistentSessionRepository(this.database);

  /// Pool con transacciones de autenticación acotadas.
  final Database database;

  /// Ejecuta una operación predefinida sobre hashes y devuelve su estado.
  Future<Map<String, dynamic>> execute(
    String operation,
    Map<String, Object?> data, {
    RequestMetadata? metadata,
  }) => database.withAuthenticationTransaction(
    metadata: metadata ?? RequestMetadata.create(),
    action: (tx) async {
      final rows = await tx.execute(
        Sql.named('SELECT public.fn_sesion_acceso(@operation,@data::jsonb)'),
        parameters: {'operation': operation, 'data': jsonEncode(data)},
      );
      return Map<String, dynamic>.from(rows.single[0]! as Map);
    },
  );
}
