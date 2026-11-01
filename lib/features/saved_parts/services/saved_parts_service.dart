import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/features/offers/services/offer_service.dart';
import 'package:re_api/features/saved_parts/dto/save_part_request.dart';
import 'package:re_api/features/saved_parts/repositories/saved_parts_repository.dart';

/// Coordina idempotencia, recibos autorizados y persistencia de selecciones.
class SavedPartsService {
  /// Coordina idempotencia, recibos autorizados y persistencia de selecciones.
  SavedPartsService(this.repository, this.offers);

  /// Acceso SQL a las referencias guardadas del taller.
  final SavedPartsRepository repository;

  /// Servicio que valida la pertenencia y vigencia de los recibos.
  final OfferService offers;

  /// Guarda una decisión validada sin comprar ni modificar el diagnóstico.
  Future<Map<String, Object?>> save(
    SavePartRequest input,
    AuthIdentity identity,
  ) async {
    final existing = await repository.retry(input, identity);
    if (existing != null) return existing;
    final receipt = offers.receipt(input.token, identity);
    return repository.save(input, receipt, identity);
  }
}
