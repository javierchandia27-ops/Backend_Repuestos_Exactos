import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/auth/session_store.dart';

Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(
      statusCode: HttpStatus.methodNotAllowed,
      headers: {'allow': 'GET'},
    );
  }
  final session = context.read<AuthSession>();
  return Response.json(
    body: {
      ...session.identity.toPublicJson(),
      'expires_at': session.expiresAt.toIso8601String(),
    },
  );
}
