import 'package:postgres/postgres.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/config/database_config.dart';
import 'package:re_api/http/request_metadata.dart';

/// Conexiones compartidas de la API con PostgreSQL.
class Database {
  /// Crea un pool limitado; las conexiones se abren bajo demanda.
  Database(DatabaseConfig config, {int maxConnectionCount = 5})
    : _pool = Pool<void>.withEndpoints(
        [config.endpoint],
        settings: PoolSettings(
          applicationName: 're-api',
          maxConnectionCount: maxConnectionCount,
          connectTimeout: const Duration(seconds: 5),
          queryTimeout: const Duration(seconds: 5),
          sslMode: config.sslMode,
        ),
      );

  final Pool<void> _pool;

  /// Verifica conexión, rol de aplicación y tablas base.
  /// No consulta registros de los talleres.
  Future<bool> checkConnection() async {
    final result = await _pool.execute('''
      SELECT session_user = 'app_backend_user'
        AND current_user = session_user
        AND NULLIF(current_setting('app.taller_id', true), '') IS NULL
        AND NULLIF(current_setting('app.usuario_id', true), '') IS NULL
        AND to_regclass('public.vehiculo') IS NOT NULL
        AND to_regclass('public.sesion_diagnostico') IS NOT NULL
        AND to_regclass('public.cotizacion') IS NOT NULL AS ready
    ''');
    return result.single[0] == true;
  }

  /// Metadatos para el diagnóstico local; no se exponen por HTTP.
  Future<List<String>> listTables() async {
    final result = await _pool.execute('''
      SELECT c.relname
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
      ORDER BY c.relname
    ''');
    return result.map((row) => row[0]! as String).toList();
  }

  /// Usa la función de login existente, con parámetros y sin asumir roles.
  /// Un intento fallido se confirma para conservar bloqueo y auditoría.
  Future<AuthIdentity?> authenticate(
    String email,
    String password, {
    required RequestMetadata metadata,
  }) => _pool.runTx((transaction) async {
    await _setMetadata(transaction, metadata);
    final result = await transaction.execute(
      Sql.named('''
        SELECT a.autenticado, a.usuario_id, a.usuario_id_publico,
               a.taller_id, a.taller_id_publico, a.rol::text AS rol, a.nombre
        FROM public.fn_autenticar_usuario(@email, @password) a
      '''),
      parameters: {'email': email, 'password': password},
    );
    final row = result.single.toColumnMap();
    if (row['autenticado'] != true) return null;
    return AuthIdentity(
      userId: row['usuario_id']! as int,
      workshopId: row['taller_id']! as int,
      userPublicId: row['usuario_id_publico']! as String,
      workshopPublicId: row['taller_id_publico']! as String,
      role: UserRole.values.byName(row['rol']! as String),
      name: row['nombre']! as String,
    );
  });

  /// Una petición autenticada usa una conexión y una transacción completas.
  /// El rol y contexto local se descartan tanto en COMMIT como en ROLLBACK.
  Future<T> withUserTransaction<T>(
    AuthIdentity identity, {
    required RequestMetadata metadata,
    required Future<T> Function(TxSession transaction) action,
  }) => _pool.runTx((transaction) async {
    await transaction.execute(identity.role.setLocalRole);
    await transaction.execute(
      Sql.named('''
        SELECT set_config('app.taller_id', @taller, true),
               set_config('app.usuario_id', @usuario, true)
      '''),
      parameters: {
        'taller': identity.workshopId.toString(),
        'usuario': identity.userId.toString(),
      },
    );
    await _setMetadata(transaction, metadata);
    // Revalidar cada petición: una baja o cambio de rol invalida la sesión.
    final active = await transaction.execute(
      Sql.named('''
        SELECT u.id_publico
        FROM public.usuario u
        JOIN public.taller t ON t.id = u.taller_id
        WHERE u.id = @usuario AND u.taller_id = @taller
          AND u.id_publico = @usuario_publico::uuid
          AND t.id_publico = @taller_publico::uuid
          AND u.activo AND t.activo AND u.rol::text = @rol
      '''),
      parameters: {
        'usuario': identity.userId,
        'taller': identity.workshopId,
        'usuario_publico': identity.userPublicId,
        'taller_publico': identity.workshopPublicId,
        'rol': identity.role.name,
      },
    );
    if (active.isEmpty) throw const InvalidSession();
    return action(transaction);
  });

  Future<void> _setMetadata(
    TxSession transaction,
    RequestMetadata metadata,
  ) async {
    await transaction.execute(
      Sql.named('''
        SELECT set_config('app.ip_origen', @ip, true),
               set_config('app.request_id', @request, true)
      '''),
      parameters: {'ip': metadata.ip ?? '', 'request': metadata.requestId},
    );
  }

  /// Libera todas las conexiones del pool.
  Future<void> close() => _pool.close();
}
