import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/auth/session_cookie.dart';
import 'package:re_api/auth/session_response.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/request_metadata.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, headers: {'allow': 'POST'});
  }
  SessionCookie.validateRequest(context.request);
  final token = SessionCookie.read(context.request);
  final issued = token == null
      ? null
      : await context.read<SessionStore>().renew(
          token,
          metadata: context.read<RequestMetadata>(),
        );
  if (issued == null) {
    return apiError(
      401,
      'invalid_session',
    ).copyWith(headers: {'set-cookie': SessionCookie.header(context.request)});
  }
  return issuedSessionResponse(issued, context.request);
}
