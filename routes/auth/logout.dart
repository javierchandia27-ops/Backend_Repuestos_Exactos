import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/auth/authentication_middleware.dart';
import 'package:re_api/auth/session_store.dart';

Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.post) {
    return Response(
      statusCode: HttpStatus.methodNotAllowed,
      headers: {'allow': 'POST'},
    );
  }
  context.read<SessionStore>().revoke(bearerToken(context.request)!);
  return Response(statusCode: HttpStatus.noContent);
}
