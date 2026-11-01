import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/features/offers/dto/offer_search_request.dart';
import 'package:re_api/features/offers/repositories/offer_plan_repository.dart';
import 'package:re_api/features/offers/services/offer_service.dart';
import 'package:re_api/http/request_metadata.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, headers: {'allow': 'POST'});
  }
  final input = await OfferSearchRequest.read(context.request);
  final identity = context.read<AuthSession>().identity;
  final plan = await context.read<Database>().withUserTransaction(
    identity,
    metadata: context.read<RequestMetadata>(),
    action: (tx) => OfferPlanRepository(tx).plan(input),
  );
  // La transacción ya terminó. El proveedor no ocupa conexiones PostgreSQL.
  final result = await context.read<OfferService>().search(identity, plan);
  return Response.json(body: result);
}
