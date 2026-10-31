import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/features/onboarding/services/google_token_verifier.dart';

Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, headers: {'allow': 'GET'});
  }
  final verifier = context.read<GoogleTokenVerifier>();
  return Response.json(
    body: {
      'enabled': verifier.configured,
      'client_id': verifier.configured ? verifier.clientIds.first : null,
    },
  );
}
