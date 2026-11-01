import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/features/offers/repositories/offer_plan_repository.dart';
import 'package:re_api/http/query_validation.dart';

Future<Response> onRequest(RequestContext context, String code) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, headers: {'allow': 'GET'});
  }
  validateQueryKeys(context.request.uri, {});
  final items = await OfferPlanRepository(
    context.read<TxSession>(),
  ).components(diagnosticCode(code));
  return Response.json(body: {'items': items});
}
