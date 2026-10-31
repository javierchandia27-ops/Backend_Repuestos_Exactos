import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/features/onboarding/services/google_token_verifier.dart';
import 'package:re_api/features/onboarding/services/onboarding_store.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/request_metadata.dart';

Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, headers: {'allow': 'POST'});
  }
  final verifier = context.read<GoogleTokenVerifier>();
  if (!verifier.configured) return apiError(503, 'google_not_configured');
  final store = context.read<OnboardingStore>()
    ..rateLimit(context.read<RequestMetadata>().ip ?? 'unknown');
  return Response.json(body: {'nonce': store.challenge(), 'expires_in': 600});
}
