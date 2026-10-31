import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:re_api/features/onboarding/models/google_identity.dart';
import 'package:re_api/http/api_error.dart';

/// Desafíos de corta duración. No conceden acceso a información de un taller.
class OnboardingStore {
  /// Permite inyectar el reloj para probar vencimientos.
  OnboardingStore({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final _random = Random.secure();
  final _challenges = <String, DateTime>{};
  final _pending = <String, ({GoogleIdentity identity, DateTime expires})>{};
  final _locked = <String>{};
  final _rates = <String, ({int count, DateTime expires})>{};
  String _randomToken() => base64UrlEncode(
    List.generate(32, (_) => _random.nextInt(256)),
  ).replaceAll('=', '');
  String _hash(String s) => sha256.convert(utf8.encode(s)).toString();
  void _prune() {
    final now = _clock();
    _challenges.removeWhere((_, v) => !v.isAfter(now));
    _pending.removeWhere((_, v) => !v.expires.isAfter(now));
    _rates.removeWhere((_, v) => !v.expires.isAfter(now));
  }

  /// Limita intentos y uso de memoria por origen.
  void rateLimit(String key) {
    _prune();
    final now = _clock();
    final r = _rates[key];
    if (r != null && r.count >= 30) {
      throw const ApiError(429, 'too_many_attempts');
    }
    if (r == null && _rates.length >= 10000) {
      throw const ApiError(503, 'auth_capacity_reached');
    }
    _rates[key] = (
      count: (r?.count ?? 0) + 1,
      expires: r?.expires ?? now.add(const Duration(minutes: 5)),
    );
  }

  /// Genera un nonce aleatorio válido por diez minutos.
  String challenge() {
    _prune();
    if (_challenges.length >= 10000) {
      throw const ApiError(503, 'auth_capacity_reached');
    }
    final nonce = _randomToken();
    _challenges[_hash(nonce)] = _clock().add(const Duration(minutes: 10));
    return nonce;
  }

  /// Consume atómicamente un nonce no vencido.
  void consumeChallenge(String nonce) {
    final expires = _challenges.remove(_hash(nonce));
    if (expires == null || !expires.isAfter(_clock())) {
      throw const ApiError(401, 'invalid_google_challenge');
    }
  }

  /// Crea un ticket temporal sin permisos de taller.
  String issue(GoogleIdentity identity) {
    _prune();
    if (_pending.length >= 10000) {
      throw const ApiError(503, 'auth_capacity_reached');
    }
    final token = _randomToken();
    _pending[_hash(token)] = (
      identity: identity,
      expires: _clock().add(const Duration(minutes: 10)),
    );
    return token;
  }

  /// Consume el ticket al completar y evita uso simultáneo.
  Future<T> use<T>(
    String token,
    Future<T> Function(GoogleIdentity) action,
  ) async {
    _prune();
    final key = _hash(token);
    final p = _pending[key];
    if (p == null || !_locked.add(key)) {
      throw const ApiError(401, 'invalid_onboarding_token');
    }
    try {
      final result = await action(p.identity);
      _pending.remove(key);
      return result;
    } finally {
      _locked.remove(key);
    }
  }
}
