import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:re_api/features/offers/models/offer.dart';
import 'package:re_api/features/offers/models/offer_search_plan.dart';
import 'package:re_api/features/offers/providers/offer_provider.dart';
import 'package:re_api/features/offers/providers/provider_http.dart';
import 'package:re_api/features/offers/services/ebay_tokens.dart';
import 'package:re_api/http/api_error.dart';

/// Browse API en EBAY_US. Una búsqueda por palabras no acredita compatibilidad.
class EbayProvider implements OfferProvider {
  /// Comparte transporte y gestor de tokens del entorno seleccionado.
  EbayProvider(this.tokens, this.client);

  /// Autenticación de aplicación, sin sesión de comprador.
  final EbayTokens tokens;

  /// Transporte acotado a los hosts oficiales de eBay.
  final http.Client client;
  @override
  String get id => 'ebay';
  @override
  String get environment => tokens.config.environment;

  // Traducciones explícitas del catálogo local; no se infiere una reparación.
  static const _terms = {
    'Bujía': 'spark plug',
    'Bobina de encendido': 'ignition coil',
    'Inyector de combustible': 'fuel injector',
    'Filtro de aire': 'air filter',
    'Sensor de velocidad de rueda': 'wheel speed sensor',
    'Sensor de oxígeno': 'oxygen sensor',
    'Sensor de flujo de aire (MAF)': 'mass air flow sensor',
    'Catalizador': 'catalytic converter',
    'Válvula EGR': 'EGR valve',
    'Sensor de posición del cigüeñal': 'crankshaft position sensor',
  };
  @override
  String queryFor(OfferSearchPlan plan) {
    final term = _terms[plan.componentName] ?? plan.componentName;
    final suffix = plan.query.startsWith(plan.componentName)
        ? plan.query.substring(plan.componentName.length)
        : '';
    final query = '$term$suffix'.trim();
    return String.fromCharCodes(query.runes.take(100));
  }

  @override
  Future<List<Offer>> search(String query) async {
    if (query.trim().isEmpty || query.runes.length > 100) {
      throw const ApiError(400, 'invalid_offer_search');
    }
    Future<http.Response> request(String token) => providerRequest(
      client,
      'GET',
      Uri.https(tokens.config.apiHost, '/buy/browse/v1/item_summary/search', {
        'q': query,
        'limit': '20',
      }),
      headers: {
        'authorization': 'Bearer $token',
        'accept': 'application/json',
        'X-EBAY-C-MARKETPLACE-ID': 'EBAY_US',
      },
    );
    final token = await tokens.accessToken();
    var response = await request(token);
    if (response.statusCode == 401) {
      response = await request(await tokens.accessToken(rejectedToken: token));
    }
    if (response.statusCode == 401) {
      throw const ApiError(503, 'ebay_credentials_rejected');
    }
    if (response.statusCode == 403) {
      throw const ApiError(502, 'provider_access_denied');
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
          data['total'] is! int ||
          (data['total'] as int) < 0 ||
          (data['itemSummaries'] != null && data['itemSummaries'] is! List)) {
        throw const FormatException();
      }
      if (data['itemSummaries'] == null && data['total'] != 0) {
        throw const FormatException();
      }
      final now = DateTime.now().toUtc();
      final seen = <String>{};
      final offers = <Offer>[];
      for (final row in (data['itemSummaries'] as List? ?? const []).take(20)) {
        if (row is! Map<String, dynamic>) throw const FormatException();
        final itemId = row['itemId'];
        final title = row['title'];
        final rawUrl = row['itemWebUrl'];
        final price = row['price'];
        if (itemId is! String ||
            !RegExp(r'^v1\|[0-9]{1,20}\|[0-9]{1,20}$').hasMatch(itemId) ||
            title is! String ||
            title.trim().isEmpty ||
            title.length > 500 ||
            rawUrl is! String ||
            price is! Map<String, dynamic> ||
            price['value'] is! String ||
            !RegExp(
              r'^[0-9]{1,15}(?:\.[0-9]{1,4})?$',
            ).hasMatch(price['value'] as String) ||
            price['currency'] is! String ||
            !RegExp(r'^[A-Z]{3}$').hasMatch(price['currency'] as String) ||
            row['buyingOptions'] is! List ||
            !(row['buyingOptions'] as List).contains('FIXED_PRICE') ||
            !safeUrl(Uri.tryParse(rawUrl), environment)) {
          throw const FormatException();
        }
        if (!seen.add(itemId)) continue;
        offers.add(
          Offer(
            id: itemId,
            title: title,
            price: price['value'] as String,
            currency: price['currency'] as String,
            url: rawUrl,
            queriedAt: now,
            provider: id,
            environment: environment,
          ),
        );
      }
      return offers;
    } on FormatException {
      throw const ApiError(502, 'provider_invalid_response');
    }
  }

  /// Solo enlaces HTTPS del entorno correspondiente, sin autoridad extra.
  static bool safeUrl(Uri? url, String environment) {
    if (url == null ||
        url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        (url.hasPort && url.port != 443) ||
        url.hasFragment ||
        !url.path.startsWith('/itm/') ||
        url.path.length <= 5 ||
        url.toString().length > 2000) {
      return false;
    }
    final sandbox =
        url.host == 'sandbox.ebay.com' ||
        url.host.endsWith('.sandbox.ebay.com');
    return environment == 'sandbox'
        ? sandbox
        : environment == 'production' &&
              !sandbox &&
              (url.host == 'ebay.com' || url.host.endsWith('.ebay.com'));
  }
}
