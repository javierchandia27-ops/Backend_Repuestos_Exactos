import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/features/onboarding/dto/onboarding_payload.dart';
import 'package:re_api/features/onboarding/repositories/invitation_repository.dart';
import 'package:re_api/http/api_error.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.read<AuthSession>().identity.role != UserRole.propietario) {
    return apiError(403, 'owner_required');
  }
  final repository = InvitationRepository(context.read<TxSession>());
  if (context.request.method == HttpMethod.get) {
    return Response.json(body: {'data': await repository.list()});
  }
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, headers: {'allow': 'GET, POST'});
  }
  final body = await OnboardingPayload.read(context.request, {'email', 'role'});
  final email = OnboardingPayload.text(
    body,
    'email',
    max: 254,
  ).trim().toLowerCase();
  if (body.containsKey('role') && body['role'] != 'mecanico') {
    throw const ApiError(400, 'mechanic_invitation_required');
  }
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    throw const ApiError(400, 'invalid_invitation_payload');
  }
  return Response.json(
    statusCode: 201,
    body: await repository.create(email),
  );
}
