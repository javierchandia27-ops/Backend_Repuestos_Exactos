import 'dart:convert';
import 'dart:math';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/features/offers/models/offer_receipt.dart';
import 'package:re_api/features/offers/models/offer_search_plan.dart';
import 'package:re_api/features/offers/providers/mercadolibre_provider.dart';
import 'package:re_api/http/api_error.dart';

/// Recibos breves ligados al usuario y taller: el cliente nunca fija
/// precio/URL.
class OfferService {
  /// Coordina consultas y genera recibos temporales por usuario y taller.
  OfferService(this.provider);

  /// Adaptador externo usado fuera de transacciones SQL.
  final MercadoLibreProvider provider;
  final _receipts = <String, OfferReceipt>{};
  final _requests = <int, DateTime>{};
  final _busy = <int>{};

  /// Consulta resultados externos y conserva su origen y límites.
  Future<Map<String, Object?>> search(
    AuthIdentity identity,
    OfferSearchPlan plan,
  ) async {
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
      final offers = await provider.search(plan.query);
      final expires = DateTime.now().toUtc().add(const Duration(minutes: 10));
      return {
        'provider': 'mercadolibre',
        'query': plan.query,
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
