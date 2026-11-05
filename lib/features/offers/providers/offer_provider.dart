import 'package:re_api/features/offers/models/offer.dart';
import 'package:re_api/features/offers/models/offer_search_plan.dart';

/// Contrato común para fuentes externas, fuera de las transacciones SQL.
abstract interface class OfferProvider {
  /// Identificador estable de la fuente externa.
  String get id;

  /// Entorno fijado por el servidor.
  String get environment;

  /// Adapta palabras de búsqueda del contexto validado.
  String queryFor(OfferSearchPlan plan);

  /// Devuelve resultados temporales, sin conservar contenido comercial.
  Future<List<Offer>> search(String query);
}
