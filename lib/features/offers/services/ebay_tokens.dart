import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:re_api/config/ebay_config.dart';
import 'package:re_api/features/offers/providers/provider_http.dart';
import 'package:re_api/http/api_error.dart';

/// Tokens de aplicación en memoria: Client Credentials no emite refresh token.
class EbayTokens {
  /// Permite probar el vencimiento con un reloj controlado.
  EbayTokens(this.config, this.client, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Credenciales privadas y entorno de emisión.
  final EbayConfig config;

  /// Transporte compartido del adaptador.
  final http.Client client;
  final DateTime Function() _clock;
  String? _token;
  DateTime? _expires;
  Future<String>? _loading;

  /// Reutiliza acceso válido y serializa emisiones concurrentes.
  Future<String> accessToken({String? rejectedToken}) async {
    // Una respuesta 401 tardía no descarta un token más reciente.
    if (rejectedToken != null && _token == rejectedToken) {
      _token = null;
      _expires = null;
    }
    final pending = _loading;
    if (pending != null) return pending;
    if (_token != null &&
        _expires!.isAfter(_clock().toUtc().add(const Duration(seconds: 60)))) {
      return _token!;
    }
    final task = _mint();
    _loading = task;
    try {
      return await task;
    } finally {
      _loading = null;
    }
  }

  Future<String> _mint() async {
    if (!config.configured) throw const ApiError(503, 'ebay_not_configured');
    final credentials = base64Encode(
      utf8.encode([config.clientId, config.clientSecret].join(':')),
    );
    final response = await providerRequest(
      client,
      'POST',
      Uri.https(config.apiHost, '/identity/v1/oauth2/token'),
      headers: {
        'authorization': 'Basic $credentials',
        'accept': 'application/json',
      },
      fields: {
        'grant_type': 'client_credentials',
        'scope': 'https://api.ebay.com/oauth/api_scope',
      },
    );
    if ({400, 401, 403}.contains(response.statusCode)) {
      throw const ApiError(503, 'ebay_credentials_rejected');
    }
    if (response.statusCode == 429) {
      throw const ApiError(503, 'provider_rate_limited');
    }
    if (response.statusCode != 200) {
      throw const ApiError(502, 'provider_unavailable');
    }
    try {
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> ||
          data['access_token'] is! String ||
          (data['access_token'] as String).isEmpty ||
          (data['access_token'] as String).length > 16384 ||
          data['expires_in'] is! int ||
          (data['expires_in'] as int) < 1 ||
          (data['expires_in'] as int) > 86400) {
        throw const FormatException();
      }
      _token = data['access_token'] as String;
      _expires = _clock().toUtc().add(
        Duration(seconds: data['expires_in'] as int),
      );
      return _token!;
    } on FormatException {
      throw const ApiError(502, 'provider_invalid_response');
    }
  }
}
