import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/auth/authentication_middleware.dart';
import 'package:re_api/auth/session_cookie.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/http/request_metadata.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, headers: {'allow': 'POST'});
  }
  final refresh = SessionCookie.read(context.request);
  if (refresh != null) SessionCookie.validateRequest(context.request);
  await context.read<SessionStore>().invalidate(
    access: bearerToken(context.request),
    refresh: refresh,
    metadata: context.read<RequestMetadata>(),
  );
  return Response(
    statusCode: 204,
    headers: {
      'set-cookie': SessionCookie.header(context.request),
      'cache-control': 'no-store',
    },
  );
}
