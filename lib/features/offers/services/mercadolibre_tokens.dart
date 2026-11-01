import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:re_api/config/mercadolibre_config.dart';
import 'package:re_api/features/offers/providers/mercadolibre_http.dart';
import 'package:re_api/http/api_error.dart';

/// Un solo proceso escribe este archivo privado; la renovación se serializa.
class MercadoLibreTokens {
  /// Comparte configuración privada y transporte con el adaptador.
  MercadoLibreTokens(this.config, this.client);

  /// Credenciales del servidor, nunca serializadas por la API.
  final MercadoLibreConfig config;

  /// Transporte HTTP del proveedor.
  final http.Client client;
  Future<String>? _refreshing;

  /// Reutiliza el acceso vigente o renueva una sola vez para llamadas
  /// concurrentes.
  Future<String> accessToken({bool forceRefresh = false}) async {
    final pending = _refreshing;
    if (pending != null) return pending;
    final task = _load(forceRefresh: forceRefresh);
    _refreshing = task;
    try {
      return await task;
    } finally {
      _refreshing = null;
    }
  }

  Future<String> _load({required bool forceRefresh}) async {
    if (!config.configured) {
      throw const ApiError(503, 'mercadolibre_not_configured');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(await File(config.tokenFile).readAsString());
    } on FileSystemException {
      throw const ApiError(503, 'mercadolibre_authorization_required');
    } on FormatException {
      throw const ApiError(503, 'mercadolibre_authorization_required');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ApiError(503, 'mercadolibre_authorization_required');
    }
    final expires = DateTime.tryParse(decoded['expires_at']?.toString() ?? '');
    final token = decoded['access_token'];
    if (!forceRefresh &&
        token is String &&
        token.isNotEmpty &&
        expires != null &&
        expires.isAfter(
          DateTime.now().toUtc().add(const Duration(seconds: 60)),
        )) {
      return token;
    }
    final refresh = decoded['refresh_token'];
    if (refresh is! String || refresh.isEmpty) {
      throw const ApiError(503, 'mercadolibre_authorization_required');
    }
    final response = await mercadoLibreRequest(
      client,
      'POST',
      Uri.https('api.mercadolibre.com', '/oauth/token'),
      fields: {
        'grant_type': 'refresh_token',
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'refresh_token': refresh,
      },
    );
    if (response.statusCode == 400 || response.statusCode == 401) {
      throw const ApiError(503, 'mercadolibre_authorization_required');
    }
    if (response.statusCode != 200) {
      throw const ApiError(502, 'provider_unavailable');
    }
    return storeTokenResponse(config, response.body);
  }

  /// Guarda atómicamente los nuevos tokens, respetando expires_in del
  /// proveedor.
  static Future<String> storeTokenResponse(
    MercadoLibreConfig config,
    String body,
  ) async {
    final Object? data;
    try {
      data = jsonDecode(body);
    } on FormatException {
      throw const ApiError(502, 'provider_invalid_response');
    }
    if (data is! Map<String, dynamic> ||
        data['access_token'] is! String ||
        (data['access_token'] as String).isEmpty ||
        data['refresh_token'] is! String ||
        (data['refresh_token'] as String).isEmpty ||
        data['expires_in'] is! int ||
        (data['expires_in'] as int) <= 0 ||
        (data['expires_in'] as int) > 31536000) {
      throw const ApiError(502, 'provider_invalid_response');
    }
    final stored = <String, Object?>{
      'access_token': data['access_token'],
      'refresh_token': data['refresh_token'],
      'expires_at': DateTime.now()
          .toUtc()
          .add(Duration(seconds: data['expires_in'] as int))
          .toIso8601String(),
    };
    try {
      final file = File(config.tokenFile);
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(stored), flush: true);
      await temp.rename(file.path);
    } on FileSystemException {
      throw const ApiError(503, 'provider_token_storage_unavailable');
    }
    return data['access_token'] as String;
  }
}
