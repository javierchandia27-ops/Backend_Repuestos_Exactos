import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/auth/persistent_session_repository.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/request_metadata.dart';

/// Sesión privada con vencimiento absoluto, sin renovación implícita.
class AuthSession {
  /// Crea una sesión del servidor.
  const AuthSession({required this.identity, required this.expiresAt});

  /// Identidad validada al iniciar sesión.
  final AuthIdentity identity;

  /// Vencimiento UTC.
  final DateTime expiresAt;
}

/// Token que se entrega una sola vez al iniciar sesión.
class IssuedSession {
  /// Resultado de emitir una sesión.
  const IssuedSession({
    required this.token,
    required this.session,
    this.refreshToken,
    this.refreshExpiresAt,
  });

  /// Credencial de renovación entregada exclusivamente en cookie HttpOnly.
  final String? refreshToken;

  /// Vencimiento absoluto de la familia.
  final DateTime? refreshExpiresAt;

  /// Token opaco: no contiene datos del usuario ni del taller.
  final String token;

  /// Sesión guardada en el servidor.
  final AuthSession session;
}

/// Capacidad de sesiones alcanzada, sin expulsar sesiones todavía válidas.
class SessionLimitException implements Exception {
  /// Error de capacidad.
  const SessionLimitException();
}

/// Sesiones persistentes en producción; el almacén en memoria sólo sirve a
/// pruebas aisladas que no proporcionan Database.
class SessionStore {
  /// Permite ajustar el reloj y límites para pruebas sin esperar tiempo real.
  SessionStore({
    this.lifetime = const Duration(hours: 1),
    this.maxSessions = 10000,
    DateTime Function()? clock,
    Database? database,
  }) : _persistent = database == null
           ? null
           : PersistentSessionRepository(database),
       _clock = clock ?? DateTime.now {
    if (lifetime <= Duration.zero || maxSessions < 1) {
      throw ArgumentError('La duración y la capacidad deben ser positivas.');
    }
  }

  /// Duración absoluta de las sesiones nuevas.
  final Duration lifetime;

  /// Límite de memoria para sesiones activas.
  final int maxSessions;
  final DateTime Function() _clock;
  final PersistentSessionRepository? _persistent;
  final _random = Random.secure();
  final _sessions = <String, AuthSession>{};
  static final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

  /// Emite 256 bits aleatorios y guarda únicamente el hash del token.
  IssuedSession issue(AuthIdentity identity) {
    final now = _clock().toUtc();
    _sessions.removeWhere((_, session) => !session.expiresAt.isAfter(now));
    if (_sessions.length >= maxSessions) throw const SessionLimitException();
    final token = base64UrlEncode(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    ).replaceAll('=', '');
    final session = AuthSession(
      identity: identity,
      expiresAt: now.add(lifetime),
    );
    _sessions[_key(token)] = session;
    return IssuedSession(token: token, session: session);
  }

  /// Busca una sesión válida; no confía en contenido aportado por el token.
  AuthSession? resolve(String token) {
    if (!_tokenPattern.hasMatch(token)) return null;
    final key = _key(token);
    final session = _sessions[key];
    if (session == null) return null;
    if (!session.expiresAt.isAfter(_clock().toUtc())) {
      _sessions.remove(key);
      return null;
    }
    return session;
  }

  /// Revoca la sesión de forma inmediata e idempotente.
  void revoke(String token) => _sessions.remove(_key(token));

  String _newToken() => base64UrlEncode(
    List<int>.generate(32, (_) => _random.nextInt(256)),
  ).replaceAll('=', '');

  /// Emite una familia persistente; mantiene pruebas aisladas en memoria.
  Future<IssuedSession> create(
    AuthIdentity identity, {
    RequestMetadata? metadata,
  }) async {
    final repository = _persistent;
    if (repository == null) return issue(identity);
    final access = _newToken();
    final refresh = _newToken();
    final row = await repository.execute('emitir', {
      'usuario': identity.userId,
      'taller': identity.workshopId,
      'perfil': identity.role.name,
      'acceso': _key(access),
      'renovacion': _key(refresh),
      'segundos': lifetime.inSeconds,
      'limite': 604800,
      'capacidad': maxSessions,
    }, metadata: metadata);
    return _issued(row, access, refresh);
  }

  /// Resuelve contra PostgreSQL, incluso después de reiniciar la API.
  Future<AuthSession?> find(String token, {RequestMetadata? metadata}) async {
    if (!_tokenPattern.hasMatch(token)) return null;
    final repository = _persistent;
    if (repository == null) return resolve(token);
    final row = await repository.execute('resolver', {
      'acceso': _key(token),
    }, metadata: metadata);
    return row['status'] == 'authenticated' ? _session(row) : null;
  }

  /// Rota ambas credenciales, con límite absoluto de siete días.
  Future<IssuedSession?> renew(
    String token, {
    RequestMetadata? metadata,
  }) async {
    if (!_tokenPattern.hasMatch(token) || _persistent == null) return null;
    final access = _newToken();
    final refresh = _newToken();
    final row = await _persistent.execute('renovar', {
      'renovacion': _key(token),
      'nuevo_acceso': _key(access),
      'nueva_renovacion': _key(refresh),
      'segundos': lifetime.inSeconds,
    }, metadata: metadata);
    if (row['status'] == 'retry') {
      throw const ApiError(409, 'refresh_in_progress');
    }
    if (row['status'] != 'authenticated') return null;
    return _issued(row, access, refresh);
  }

  /// Revoca por acceso o cookie, también con acceso vencido.
  Future<void> invalidate({
    String? access,
    String? refresh,
    RequestMetadata? metadata,
  }) async {
    if ((access == null || !_tokenPattern.hasMatch(access)) &&
        (refresh == null || !_tokenPattern.hasMatch(refresh))) {
      return;
    }
    if (_persistent == null) {
      if (access != null) revoke(access);
      return;
    }
    await _persistent.execute('revocar', {
      if (access != null && _tokenPattern.hasMatch(access))
        'acceso': _key(access),
      if (refresh != null && _tokenPattern.hasMatch(refresh))
        'renovacion': _key(refresh),
    }, metadata: metadata);
  }

  AuthSession _session(Map<String, dynamic> row) => AuthSession(
    identity: AuthIdentity(
      userId: row['usuario_id'] as int,
      workshopId: row['taller_id'] as int,
      userPublicId: row['usuario_id_publico'] as String,
      workshopPublicId: row['taller_id_publico'] as String,
      role: UserRole.values.byName(row['perfil'] as String),
      name: row['nombre'] as String,
    ),
    expiresAt: DateTime.parse(row['expires_at'] as String).toUtc(),
  );

  IssuedSession _issued(
    Map<String, dynamic> row,
    String access,
    String refresh,
  ) {
    if (row['status'] == 'capacity') throw const SessionLimitException();
    if (row['status'] != 'authenticated') throw const InvalidSession();
    return IssuedSession(
      token: access,
      session: _session(row),
      refreshToken: refresh,
      refreshExpiresAt: DateTime.parse(
        row['refresh_expires_at'] as String,
      ).toUtc(),
    );
  }

  String _key(String token) => sha256.convert(utf8.encode(token)).toString();
}
