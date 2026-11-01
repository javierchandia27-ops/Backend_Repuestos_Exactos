import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/features/offers/services/offer_service.dart';
import 'package:re_api/features/saved_parts/dto/save_part_request.dart';
import 'package:re_api/features/saved_parts/repositories/saved_parts_repository.dart';
import 'package:re_api/features/saved_parts/services/saved_parts_service.dart';
import 'package:re_api/http/query_validation.dart';

Future<Response> onRequest(RequestContext context) async {
  final repository = SavedPartsRepository(context.read<TxSession>());
  if (context.request.method == HttpMethod.get) {
    final uri = context.request.uri;
    validateQueryKeys(uri, {'limit', 'offset'});
    return Response.json(
      body: await repository.list(
        limit: queryInteger(
          uri.queryParameters['limit'],
          fallback: 20,
          min: 1,
          max: 100,
        ),
        offset: queryInteger(
          uri.queryParameters['offset'],
          fallback: 0,
          min: 0,
          max: 100000,
        ),
      ),
    );
  } else if (context.request.method == HttpMethod.post) {
    final input = await SavePartRequest.read(context.request);
    final saved = await SavedPartsService(
      repository,
      context.read<OfferService>(),
    ).save(input, context.read<AuthSession>().identity);
    return Response.json(body: saved);
  } else {
    return Response(statusCode: 405, headers: {'allow': 'GET, POST'});
  }
}
