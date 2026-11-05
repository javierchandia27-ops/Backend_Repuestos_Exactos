import 'package:re_api/features/offers/models/offer.dart';
import 'package:re_api/features/offers/models/offer_search_plan.dart';
import 'package:re_api/features/offers/providers/offer_provider.dart';

/// Respuesta controlada exclusiva del servidor de integración aislado.
class QaOfferProvider implements OfferProvider {
  QaOfferProvider(this.id);
  @override
  final String id;
  @override
  String get environment => id == 'ebay' ? 'sandbox' : 'production';
  @override
  String queryFor(OfferSearchPlan plan) => plan.query;
  @override
  Future<List<Offer>> search(String query) async => [
    Offer(
      id: id == 'ebay' ? 'v1|110590963673|0' : 'MLC12345678',
      title: 'Sólo prueba controlada',
      price: id == 'ebay' ? '5.00' : null,
      currency: id == 'ebay' ? 'USD' : null,
      url: id == 'ebay' ? 'https://sandbox.ebay.com/itm/110590963673' : null,
      kind: id == 'ebay' ? 'listing' : 'catalog_product',
      catalogStatus: id == 'ebay' ? null : 'inactive',
      provider: id,
      environment: environment,
      queriedAt: DateTime.now().toUtc(),
    ),
  ];
}
