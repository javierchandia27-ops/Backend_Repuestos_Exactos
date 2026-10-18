import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/features/catalog/dto/catalog_dto.dart';
import 'package:re_api/features/catalog/dto/part_search_query.dart';
import 'package:re_api/features/catalog/services/catalog_service.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/query_validation.dart';

Future<Response> onRequest(RequestContext context, String code) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, headers: {'allow': 'GET'});
  }
  final normalized = diagnosticCode(code);
  final query = PartSearchQuery.parse(context.request.uri);
  final service = context.read<CatalogService>();
  if (!await service.hasCode(normalized)) return apiError(404, 'dtc_not_found');
  final page = await service.parts(
    normalized,
    model: query.model,
    year: query.year,
    limit: query.limit,
    offset: query.offset,
  );
  return Response.json(body: CatalogDto.parts(page.items, page.nextOffset));
}
