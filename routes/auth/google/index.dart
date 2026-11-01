import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/auth/session_response.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/features/onboarding/dto/onboarding_payload.dart';
import 'package:re_api/features/onboarding/repositories/google_account_repository.dart';
import 'package:re_api/features/onboarding/services/google_token_verifier.dart';
import 'package:re_api/features/onboarding/services/onboarding_store.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/request_metadata.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, headers: {'allow': 'POST'});
  }
  final store = context.read<OnboardingStore>()
    ..rateLimit(context.read<RequestMetadata>().ip ?? 'unknown');
  final body = await OnboardingPayload.read(context.request, {
    'id_token',
    'nonce',
  });
  final nonce = OnboardingPayload.text(body, 'nonce', min: 43, max: 43);
  store.consumeChallenge(nonce);
  final google = await context.read<GoogleTokenVerifier>().verify(
    OnboardingPayload.text(body, 'id_token'),
    nonce,
  );
  final row = await GoogleAccountRepository(
    context.read<Database>(),
  ).access(google, context.read<RequestMetadata>());
  if (row['status'] == 'authenticated') {
    return sessionResponse(
      context.read<SessionStore>(),
      GoogleAccountRepository.identity(row),
      request: context.request,
      metadata: context.read<RequestMetadata>(),
    );
  }
  if (row['status'] == 'profile_not_enabled') {
    throw const ApiError(403, 'profile_not_enabled');
  }
  if (row['status'] != 'onboarding') {
    throw const ApiError(403, 'account_disabled');
  }
  return Response.json(
    body: {
      'status': 'onboarding',
      'onboarding_token': store.issue(google),
      'email': google.email,
      'name': google.name,
      'requires_link': row['requires_link'],
      'can_register': google.authoritativeEmail,
      'expires_in': 600,
    },
  );
}
