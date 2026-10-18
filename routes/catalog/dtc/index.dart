import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/features/catalog/dto/catalog_dto.dart';
import 'package:re_api/features/catalog/services/catalog_service.dart';
import 'package:re_api/http/query_validation.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, headers: {'allow': 'GET'});
  }
  final uri = context.request.uri;
  validateQueryKeys(uri, {'q', 'limit'});
  final prefix = diagnosticCode(uri.queryParameters['q'] ?? '', prefix: true);
  final limit = queryInteger(
    uri.queryParameters['limit'],
    fallback: 20,
    min: 1,
    max: 100,
  );
  final page = await context.read<CatalogService>().codes(prefix, limit);
  return Response.json(
    body: CatalogDto.codes(page.items, hasMore: page.hasMore),
  );
}
