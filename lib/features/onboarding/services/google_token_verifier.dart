import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
import 'package:re_api/features/onboarding/models/google_identity.dart';
import 'package:re_api/http/api_error.dart';

/// Verifica localmente RS256 con las claves públicas de Google en caché.
class GoogleTokenVerifier {
  /// Configura audiencias confiables y dependencias para pruebas.
  GoogleTokenVerifier(
    this.clientIds, {
    http.Client? client,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  /// Lee los Client IDs del entorno del servidor.
  factory GoogleTokenVerifier.load() {
    final env = DotEnv(quiet: true)..load();
    final raw =
        Platform.environment['GOOGLE_CLIENT_IDS'] ??
        env['GOOGLE_CLIENT_IDS'] ??
        '';
    return GoogleTokenVerifier(
      raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet(),
    );
  }

  /// Audiencias permitidas; la primera es el cliente web.
  final Set<String> clientIds;
  final http.Client _client;
  final DateTime Function() _clock;
  JsonWebKeyStore? _keys;
  Set<String> _keyIds = {};
  late DateTime _expires;
  late DateTime _fetched;
  Future<void>? _loading;

  /// Indica si se configuró alguna audiencia.
  bool get configured => clientIds.isNotEmpty;

  Future<void> _refresh() async {
    if (_loading != null) return _loading;
    _loading = _download();
    try {
      await _loading;
    } finally {
      _loading = null;
    }
  }

  Future<void> _download() async {
    try {
      final response = await _client
          .get(Uri.https('www.googleapis.com', '/oauth2/v3/certs'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200 || response.bodyBytes.length > 65536) {
        throw const FormatException();
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final keys = (json['keys'] as List).cast<Map<String, dynamic>>();
      if (keys.isEmpty) throw const FormatException();
      final store = JsonWebKeyStore();
      for (final key in keys) {
        store.addKey(JsonWebKey.fromJson(key));
      }
      _keys = store;
      _keyIds = keys.map((k) => k['kid'] as String).toSet();
      final age =
          int.tryParse(
            RegExp(r'max-age=(\d+)')
                    .firstMatch(response.headers['cache-control'] ?? '')
                    ?.group(1) ??
                '',
          ) ??
          3600;
      _fetched = _clock().toUtc();
      _expires = _fetched.add(Duration(seconds: age.clamp(0, 21600)));
    } on Object {
      throw const ApiError(503, 'google_unavailable');
    }
  }

  /// Valida firma, audiencia, emisor, tiempo, correo y nonce.
  Future<GoogleIdentity> verify(String token, String nonce) async {
    if (!configured) throw const ApiError(503, 'google_not_configured');
    Map<String, dynamic> header;
    JsonWebToken jwt;
    try {
      final parts = token.split('.');
      if (parts.length != 3 || token.length > 8192) {
        throw const FormatException();
      }
      header =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts.first))),
              )
              as Map<String, dynamic>;
      if (header['alg'] != 'RS256' ||
          header['kid'] is! String ||
          header.containsKey('crit')) {
        throw const FormatException();
      }
      jwt = JsonWebToken.unverified(token);
    } on Object {
      throw const ApiError(401, 'invalid_google_token');
    }
    final now = _clock().toUtc();
    if (_keys == null ||
        !_expires.isAfter(now) ||
        (!_keyIds.contains(header['kid']) &&
            now.difference(_fetched) > const Duration(minutes: 1))) {
      await _refresh();
    }
    if (!_keyIds.contains(header['kid']) ||
        !await jwt.verify(_keys!, allowedArguments: ['RS256'])) {
      throw const ApiError(401, 'invalid_google_token');
    }
    try {
      final c = jwt.claims;
      final audience = c['aud'];
      final exp = c['exp'];
      final iat = c['iat'];
      final sub = c['sub'];
      final email = c['email'];
      if (!{
            'accounts.google.com',
            'https://accounts.google.com',
          }.contains(c['iss']) ||
          audience is! String ||
          !clientIds.contains(audience) ||
          (c['azp'] != null && !clientIds.contains(c['azp'])) ||
          exp is! num ||
          exp * 1000 <= now.millisecondsSinceEpoch ||
          iat is! num ||
          iat * 1000 >
              now.add(const Duration(seconds: 60)).millisecondsSinceEpoch ||
          c['nonce'] != nonce ||
          c['email_verified'] != true ||
          sub is! String ||
          sub.isEmpty ||
          sub.length > 255 ||
          email is! String ||
          email.length > 254 ||
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
        throw const FormatException();
      }
      final normalized = email.toLowerCase();
      final name =
          c['name'] is String && (c['name'] as String).trim().isNotEmpty
          ? (c['name'] as String).trim()
          : normalized;
      return GoogleIdentity(
        subject: sub,
        email: normalized,
        name: name.length > 200 ? name.substring(0, 200) : name,
        authoritativeEmail:
            normalized.endsWith('@gmail.com') ||
            (c['hd'] is String && (c['hd'] as String).isNotEmpty),
      );
    } on Object {
      throw const ApiError(401, 'invalid_google_token');
    }
  }

  /// Libera el cliente HTTP de la caché de claves.
  void close() => _client.close();
}
