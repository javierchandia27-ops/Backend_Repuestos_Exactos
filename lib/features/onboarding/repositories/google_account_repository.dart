import 'package:postgres/postgres.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/features/onboarding/models/google_identity.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/request_metadata.dart';

/// Resuelve identidades mediante la función restringida de RE-db.
class GoogleAccountRepository {
  /// Recibe el pool de autenticación de la aplicación.
  const GoogleAccountRepository(this.database);

  /// Conexiones de la API, sin acceso de superusuario.
  final Database database;

  /// Ejecuta una operación parametrizada con auditoría.
  Future<Map<String, dynamic>> access(
    GoogleIdentity google,
    RequestMetadata metadata, {
    String action = 'login',
    String? workshopName,
    String? invitationHash,
    int? linkUser,
  }) async {
    try {
      return await database.withAuthenticationTransaction(
        metadata: metadata,
        action: (tx) async {
          final rows = await tx.execute(
            Sql.named('''
          SELECT public.fn_google_acceso(@subject,@email,@name,@action,@workshop,@invitation,@link_user,@authoritative)
        '''),
            parameters: {
              'subject': google.subject,
              'email': google.email,
              'name': google.name,
              'action': action,
              'workshop': workshopName,
              'invitation': invitationHash,
              'link_user': linkUser,
              'authoritative': google.authoritativeEmail,
            },
          );
          return Map<String, dynamic>.from(rows.single[0]! as Map);
        },
      );
    } on ServerException catch (e) {
      if (e.code == 'RE021') throw const ApiError(403, 'account_disabled');
      if (e.code == '23505') throw const ApiError(409, 'account_conflict');
      rethrow;
    }
  }

  /// Convierte el resultado autenticado de PostgreSQL.
  static AuthIdentity identity(Map<String, dynamic> row) => AuthIdentity(
    userId: row['usuario_id'] as int,
    workshopId: row['taller_id'] as int,
    userPublicId: row['usuario_id_publico'] as String,
    workshopPublicId: row['taller_id_publico'] as String,
    role: UserRole.values.byName(row['perfil'] as String),
    name: row['nombre'] as String,
  );
}
