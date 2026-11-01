import 'package:re_api/features/offers/models/offer.dart';
import 'package:re_api/features/offers/models/offer_search_plan.dart';

/// Recibo temporal que vincula resultado, contexto y persona autorizada.
class OfferReceipt {
  /// Recibo temporal que vincula resultado, contexto y persona autorizada.
  const OfferReceipt({
    required this.offer,
    required this.plan,
    required this.userId,
    required this.workshopId,
    required this.expiresAt,
  });

  /// Resultado validado en el servidor, nunca reconstruido desde el cliente.
  final Offer offer;

  /// Contexto de falla y vehículo revalidado en PostgreSQL.
  final OfferSearchPlan plan;

  /// Identificador interno del autor autorizado.
  final int userId;

  /// Identificador interno del taller autorizado.
  final int workshopId;

  /// Vencimiento UTC del recibo de selección.
  final DateTime expiresAt;
}
