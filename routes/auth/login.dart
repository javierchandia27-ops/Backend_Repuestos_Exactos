import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/auth/login_credentials.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/request_metadata.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(
      statusCode: HttpStatus.methodNotAllowed,
      headers: {'allow': 'POST'},
    );
  }
  final credentials = await LoginCredentials.read(context.request);
  final identity = await context.read<Database>().authenticate(
    credentials.email,
    credentials.password,
    metadata: context.read<RequestMetadata>(),
  );
  if (identity == null) return apiError(401, 'invalid_credentials');
  final sessions = context.read<SessionStore>();
  final issued = sessions.issue(identity);
  return Response.json(
    body: {
      'access_token': issued.token,
      'token_type': 'Bearer',
      'expires_in': sessions.lifetime.inSeconds,
      'expires_at': issued.session.expiresAt.toIso8601String(),
      ...identity.toPublicJson(),
    },
  );
}
