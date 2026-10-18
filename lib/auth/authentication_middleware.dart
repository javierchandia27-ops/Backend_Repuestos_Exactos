import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/request_metadata.dart';

/// Obtiene únicamente un token Bearer; no acepta identidad en headers o query.
String? bearerToken(Request request) {
  final header = request.headers['authorization'];
  if (header == null) return null;
  return RegExp(
    r'^Bearer ([A-Za-z0-9_-]{43})$',
    caseSensitive: false,
  ).firstMatch(header)?.group(1);
}

/// Protege por defecto todas las rutas salvo estado y login.
Middleware authenticationMiddleware({
  String? Function(Request)? clientIp,
}) => (handler) {
  return (context) async {
    String? token;
    final sessions = context.read<SessionStore>();
    try {
      final metadata = RequestMetadata.create(
        ip: clientIp != null
            ? clientIp(context.request)
            : context.request.connectionInfo.remoteAddress.address,
      );
      final enriched = context.provide<RequestMetadata>(() => metadata);
      final path = context.request.uri.path;
      const publicPaths = {'/', '/health/database', '/auth/login'};
      Response response;
      if (publicPaths.contains(path)) {
        response = await handler(enriched);
      } else {
        token = bearerToken(context.request);
        final session = token == null ? null : sessions.resolve(token);
        if (session == null) return apiError(401, 'invalid_session');
        final authenticated = enriched.provide<AuthSession>(() => session);
        if (path == '/auth/logout') {
          response = await handler(authenticated);
        } else {
          response = await context.read<Database>().withUserTransaction(
            session.identity,
            metadata: metadata,
            action: (transaction) async {
              final response = await handler(
                authenticated.provide<TxSession>(() => transaction),
              );
              if (response.statusCode >= 400) throw _RollbackResponse(response);
              return response;
            },
          );
        }
      }
      return response.copyWith(headers: {'cache-control': 'no-store'});
    } on _RollbackResponse catch (error) {
      return error.response.copyWith(headers: {'cache-control': 'no-store'});
    } on InvalidSession catch (_) {
      if (token != null) sessions.revoke(token);
      return apiError(401, 'invalid_session');
    } on ApiError catch (error) {
      return apiError(error.statusCode, error.code);
    } on SessionLimitException catch (_) {
      return apiError(503, 'session_capacity_reached');
    } on PgException catch (_) {
      return apiError(503, 'database_unavailable');
    } on SocketException catch (_) {
      return apiError(503, 'database_unavailable');
    } on TimeoutException catch (_) {
      return apiError(503, 'request_timeout');
    }
  };
};

class _RollbackResponse implements Exception {
  const _RollbackResponse(this.response);
  final Response response;
}
