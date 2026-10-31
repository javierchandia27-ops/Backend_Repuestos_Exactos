import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/features/onboarding/repositories/invitation_repository.dart';
import 'package:re_api/http/api_error.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, headers: {'allow': 'POST'});
  }
  if (context.read<AuthSession>().identity.role != UserRole.propietario) {
    return apiError(403, 'owner_required');
  }
  final uuid = RegExp(
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  if (!uuid.hasMatch(id)) {
    throw const ApiError(400, 'invalid_invitation');
  }
  if (!await InvitationRepository(context.read<TxSession>()).revoke(id)) {
    return apiError(404, 'invitation_not_found');
  }
  return Response(statusCode: 204);
}
