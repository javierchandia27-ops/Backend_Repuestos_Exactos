import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/http/api_error.dart';

/// Cookie de renovación host-only; nunca se expone al JavaScript del frontend.
class SessionCookie {
  /// Nombre estable de la cookie de la API.
  static const name = 're_refresh';

  /// Lee una única credencial; rechaza formatos ambiguos.
  static String? read(Request request) {
    final values = (request.headers['cookie'] ?? '')
        .split(';')
        .map((v) => v.trim())
        .where((v) => v.startsWith('$name='))
        .toList();
    if (values.length != 1) return null;
    final token = values.single.substring(name.length + 1);
    return RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token) ? token : null;
  }

  /// Obliga a usar una petición no simple. CORS comprueba el Origin exacto.
  static void validateRequest(Request request) {
    if (request.headers['x-re-session'] != '1') {
      throw const ApiError(403, 'session_request_required');
    }
  }

  /// Sólo HTTP loopback de desarrollo puede usar cookie sin Secure.
  static String header(Request request, {String? token, DateTime? expiresAt}) {
    final local = {'localhost', '127.0.0.1', '::1'}.contains(request.uri.host);
    final cookie = Cookie(name, token ?? '')
      ..httpOnly = true
      ..secure = !(local && request.uri.scheme == 'http')
      ..sameSite = SameSite.strict
      ..path = '/auth'
      ..maxAge = token == null
          ? 0
          : (expiresAt!
                .difference(DateTime.now().toUtc())
                .inSeconds
                .clamp(0, 604800))
      ..expires =
          expiresAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return cookie.toString();
  }
}
