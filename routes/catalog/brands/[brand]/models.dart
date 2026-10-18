import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/features/catalog/dto/catalog_dto.dart';
import 'package:re_api/features/catalog/services/catalog_service.dart';
import 'package:re_api/http/query_validation.dart';

Future<Response> onRequest(RequestContext context, String brand) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, headers: {'allow': 'GET'});
  }
  validateQueryKeys(context.request.uri, {});
  return Response.json(
    body: CatalogDto.options(
      await context.read<CatalogService>().models(publicUuid(brand)),
    ),
  );
}
