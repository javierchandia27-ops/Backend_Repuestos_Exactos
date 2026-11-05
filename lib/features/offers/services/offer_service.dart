import 'dart:convert';
import 'dart:math';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/features/offers/models/offer_receipt.dart';
import 'package:re_api/features/offers/models/offer_search_plan.dart';
import 'package:re_api/features/offers/providers/offer_provider.dart';
import 'package:re_api/http/api_error.dart';

/// Recibos breves ligados al usuario y taller: el cliente nunca fija
/// precio/URL.
class OfferService {
  /// Coordina consultas y genera recibos temporales por usuario y taller.
  OfferService(
    this.provider, {
    Iterable<OfferProvider> additionalProviders = const [],
  }) {
    for (final source in [provider, ...additionalProviders]) {
      if (_providers.containsKey(source.id)) {
        throw ArgumentError('Proveedor duplicado.');
      }
      _providers[source.id] = source;
    }
  }

  /// Adaptador externo usado fuera de transacciones SQL.
  final OfferProvider provider;
  final _providers = <String, OfferProvider>{};
  final _receipts = <String, OfferReceipt>{};
  final _requests = <int, DateTime>{};
  final _busy = <int>{};

  /// Consulta resultados externos y conserva su origen y límites.
  Future<Map<String, Object?>> search(
    AuthIdentity identity,
    OfferSearchPlan plan, {
    String providerId = 'mercadolibre',
  }) async {
    final source = _providers[providerId];
    if (source == null) throw const ApiError(503, 'provider_not_configured');
    final now = DateTime.now().toUtc();
    _receipts.removeWhere((_, v) => !v.expiresAt.isAfter(now));
    _requests.removeWhere((_, v) => now.difference(v).inMinutes >= 1);
    if (_busy.contains(identity.userId) ||
        (_requests[identity.userId]?.isAfter(
              now.subtract(const Duration(seconds: 2)),
            ) ??
            false)) {
      throw const ApiError(429, 'too_many_attempts');
    }
    if (_receipts.length > 1980 || _requests.length >= 1000) {
      throw const ApiError(503, 'offer_capacity_reached');
    }
    _requests[identity.userId] = now;
    _busy.add(identity.userId);
    try {
      final query = source.queryFor(plan);
      final offers = await source.search(query);
      if (offers.any(
        (offer) =>
            offer.provider != source.id ||
            offer.environment != source.environment,
      )) {
        throw const ApiError(502, 'provider_invalid_response');
      }
      final expires = DateTime.now().toUtc().add(const Duration(minutes: 10));
      return {
        'provider': source.id,
        'environment': source.environment,
        'query': query,
        'component_name': plan.componentName,
        'compatibility': 'unverified',
        'items': offers.map((offer) {
          final token = base64Url
              .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
              .replaceAll('=', '');
          _receipts[token] = OfferReceipt(
            offer: offer,
            plan: plan,
            userId: identity.userId,
            workshopId: identity.workshopId,
            expiresAt: expires,
          );
          return {
            ...offer.toJson(),
            'offer_token': token,
            'expires_at': expires.toIso8601String(),
          };
        }).toList(),
      };
    } finally {
      _busy.remove(identity.userId);
    }
  }

  /// Resuelve un recibo vigente que pertenezca al usuario y taller.
  OfferReceipt receipt(String token, AuthIdentity identity) {
    final receipt = _receipts[token];
    if (receipt == null ||
        receipt.userId != identity.userId ||
        receipt.workshopId != identity.workshopId ||
        !receipt.expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const ApiError(409, 'offer_expired');
    }
    return receipt;
  }
}
