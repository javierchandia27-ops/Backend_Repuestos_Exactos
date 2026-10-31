import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/auth/session_store.dart';

/// Emite la sesión opaca usada también por el login con contraseña.
Response sessionResponse(SessionStore sessions, AuthIdentity identity) {
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
