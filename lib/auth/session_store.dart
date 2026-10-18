import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:re_api/auth/auth_identity.dart';

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
  const IssuedSession({required this.token, required this.session});

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

/// Almacén de una instancia de API. Se vacía al reiniciar el proceso.
class SessionStore {
  /// Permite ajustar el reloj y límites para pruebas sin esperar tiempo real.
  SessionStore({
    this.lifetime = const Duration(hours: 1),
    this.maxSessions = 10000,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (lifetime <= Duration.zero || maxSessions < 1) {
      throw ArgumentError('La duración y la capacidad deben ser positivas.');
    }
  }

  /// Duración absoluta de las sesiones nuevas.
  final Duration lifetime;

  /// Límite de memoria para sesiones activas.
  final int maxSessions;
  final DateTime Function() _clock;
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

  String _key(String token) => sha256.convert(utf8.encode(token)).toString();
}
