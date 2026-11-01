import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/auth/session_cookie.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/http/request_metadata.dart';

/// Mismo contrato público para contraseña y Google; la renovación va en cookie.
Future<Response> sessionResponse(
  SessionStore sessions,
  AuthIdentity identity, {
  required Request request,
  RequestMetadata? metadata,
}) async => issuedSessionResponse(
  await sessions.create(identity, metadata: metadata),
  request,
);

/// No serializa el token de renovación en JSON.
Response issuedSessionResponse(IssuedSession issued, Request request) =>
    Response.json(
      headers: {
        'cache-control': 'no-store',
        if (issued.refreshToken != null)
          'set-cookie': SessionCookie.header(
            request,
            token: issued.refreshToken,
            expiresAt: issued.refreshExpiresAt,
          ),
      },
      body: {
        'access_token': issued.token,
        'token_type': 'Bearer',
        'expires_in': issued.session.expiresAt
            .difference(DateTime.now().toUtc())
            .inSeconds
            .clamp(0, 3600),
        'expires_at': issued.session.expiresAt.toIso8601String(),
        ...issued.session.identity.toPublicJson(),
      },
    );
