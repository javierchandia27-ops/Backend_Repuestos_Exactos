import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/auth/session_response.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/features/onboarding/dto/onboarding_payload.dart';
import 'package:re_api/features/onboarding/repositories/google_account_repository.dart';
import 'package:re_api/features/onboarding/services/onboarding_store.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/request_metadata.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, headers: {'allow': 'POST'});
  }
  final store = context.read<OnboardingStore>();
  final metadata = context.read<RequestMetadata>();
  store.rateLimit(metadata.ip ?? 'unknown');
  final body = await OnboardingPayload.read(context.request, {
    'onboarding_token',
    'action',
    'workshop_name',
    'invitation_token',
    'password',
  });
  final token = OnboardingPayload.text(
    body,
    'onboarding_token',
    min: 43,
    max: 43,
  );
  final action = OnboardingPayload.text(body, 'action', max: 20);
  if (!{'register', 'accept', 'link'}.contains(action)) {
    throw const ApiError(400, 'invalid_action');
  }
  final database = context.read<Database>();
  return store.use(token, (google) async {
    int? linkUser;
    String? workshop;
    String? invitation;
    if (action == 'register') {
      workshop = OnboardingPayload.text(
        body,
        'workshop_name',
        min: 2,
        max: 120,
      ).trim();
    }
    if (action == 'accept') {
      final raw = OnboardingPayload.text(
        body,
        'invitation_token',
        min: 43,
        max: 43,
      );
      invitation = sha256.convert(utf8.encode(raw)).toString();
    }
    if (action == 'link') {
      final password = OnboardingPayload.text(
        body,
        'password',
        max: 72,
      );
      if (utf8.encode(password).length > 72) {
        throw const ApiError(400, 'invalid_payload');
      }
      final existing = await database.authenticate(
        google.email,
        password,
        metadata: metadata,
      );
      if (existing == null) throw const ApiError(401, 'invalid_credentials');
      linkUser = existing.userId;
    }
    final row = await GoogleAccountRepository(database).access(
      google,
      metadata,
      action: action,
      workshopName: workshop,
      invitationHash: invitation,
      linkUser: linkUser,
    );
    if (row['status'] == 'profile_not_enabled') {
      throw const ApiError(403, 'profile_not_enabled');
    }
    if (row['status'] != 'authenticated') {
      throw ApiError(409, row['status'] as String);
    }
    return sessionResponse(
      context.read<SessionStore>(),
      GoogleAccountRepository.identity(row),
    );
  });
}
