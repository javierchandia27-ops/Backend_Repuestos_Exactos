import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:re_api/features/offers/models/offer.dart';
import 'package:re_api/features/offers/providers/mercadolibre_http.dart';
import 'package:re_api/features/offers/services/mercadolibre_tokens.dart';
import 'package:re_api/http/api_error.dart';

/// Adaptador de la API oficial; distingue catálogo técnico y publicaciones.
class MercadoLibreProvider {
  /// Adaptador de la API oficial; distingue catálogo técnico y publicaciones.
  MercadoLibreProvider(this.tokens, this.client);

  /// Gestor privado de acceso y renovación OAuth.
  final MercadoLibreTokens tokens;

  /// Transporte HTTP compartido de Mercado Libre.
  final http.Client client;
  bool _catalogOnly = false;

  /// Consulta resultados externos y conserva su origen y límites.
  Future<List<Offer>> search(String query) async {
    final token = await tokens.accessToken();
    if (_catalogOnly) return _catalog(query, token);
    final res = await mercadoLibreRequest(
      client,
      'GET',
      Uri.https('api.mercadolibre.com', '/sites/MLC/search', {
        'q': query,
        'limit': '20',
      }),
      headers: {'authorization': 'Bearer $token', 'accept': 'application/json'},
    );
    switch (res.statusCode) {
      case 401:
        throw const ApiError(503, 'mercadolibre_authorization_required');
      case 403:
        _catalogOnly = true;
        return _catalog(query, token);
      case 429:
        throw const ApiError(503, 'provider_rate_limited');
    }
    if (res.statusCode != 200) {
      throw const ApiError(502, 'provider_unavailable');
    }
    try {
      final data = jsonDecode(res.body);
      if (data is! Map<String, dynamic> || data['results'] is! List) {
        throw const FormatException();
      }
      final results = data['results'] as List<dynamic>;
      return results.take(20).map((raw) {
        if (raw is! Map<String, dynamic>) throw const FormatException();
        final row = raw;
        if (row['id'] is! String ||
            row['title'] is! String ||
            row['price'] is! num ||
            row['currency_id'] is! String ||
            row['permalink'] is! String) {
          throw const FormatException();
        }
        final id = row['id'] as String;
        final title = row['title'] as String;
        final price = row['price'].toString();
        final currency = row['currency_id'] as String;
        final url = Uri.parse(row['permalink'] as String);
        if (!RegExp(r'^MLC[0-9]{5,20}$').hasMatch(id) ||
            title.isEmpty ||
            title.length > 500 ||
            !RegExp(r'^[0-9]{1,15}(?:\.[0-9]{1,4})?$').hasMatch(price) ||
            !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
            !safeUrl(url)) {
          throw const FormatException();
        }
        return Offer(
          id: id,
          title: title,
          price: price,
          currency: currency,
          url: url.toString(),
          queriedAt: DateTime.now().toUtc(),
        );
      }).toList();
    } on FormatException {
      throw const ApiError(502, 'provider_invalid_response');
    }
  }

  Future<List<Offer>> _catalog(String query, String token) async {
    final res = await mercadoLibreRequest(
      client,
      'GET',
      Uri.https('api.mercadolibre.com', '/products/search', {
        'site_id': 'MLC',
        'status': 'active',
        'q': query,
        'limit': '20',
      }),
      headers: {'authorization': 'Bearer $token', 'accept': 'application/json'},
    );
    if (res.statusCode == 401) {
      throw const ApiError(503, 'mercadolibre_authorization_required');
    }
    if (res.statusCode == 403) {
      throw const ApiError(502, 'provider_access_denied');
    }
    if (res.statusCode == 429) {
      throw const ApiError(503, 'provider_rate_limited');
    }
    if (res.statusCode != 200) {
      throw const ApiError(502, 'provider_unavailable');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(res.body);
    } on FormatException {
      throw const ApiError(502, 'provider_invalid_response');
    }
    if (decoded is! Map<String, dynamic> || decoded['results'] is! List) {
      throw const ApiError(502, 'provider_invalid_response');
    }
    final results = decoded['results'] as List;
    final offers = <Offer>[];
    final ids = <String>{};
    for (final raw in results.take(20)) {
      if (raw is! Map<String, dynamic>) {
        throw const ApiError(502, 'provider_invalid_response');
      }
      final id = raw['id'];
      final name = raw['name'];
      final status = raw['status'];
      if (id is! String ||
          !RegExp(r'^MLC[0-9]{5,20}$').hasMatch(id) ||
          name is! String ||
          name.isEmpty ||
          name.length > 500 ||
          (status != 'active' && status != 'inactive')) {
        throw const ApiError(502, 'provider_invalid_response');
      }
      if (!ids.add(id)) continue;
      // El catálogo devuelve incluso referencias inactivas. No inventar
      // ofertas.
      offers.add(
        Offer(
          id: id,
          title: name,
          price: null,
          currency: null,
          url: null,
          kind: 'catalog_product',
          catalogStatus: status as String,
          queriedAt: DateTime.now().toUtc(),
        ),
      );
    }
    return offers;
  }

  /// Acepta sólo enlaces HTTPS de Mercado Libre Chile, sin credenciales.
  static bool safeUrl(Uri url) =>
      url.scheme == 'https' &&
      url.userInfo.isEmpty &&
      (!url.hasPort || url.port == 443) &&
      url.toString().length <= 2000 &&
      (url.host == 'mercadolibre.cl' || url.host.endsWith('.mercadolibre.cl'));
}
