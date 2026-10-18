import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/database/database.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(
      statusCode: HttpStatus.methodNotAllowed,
      headers: {'allow': 'GET'},
    );
  }

  try {
    final ready = await context.read<Database>().checkConnection();
    if (ready) {
      return Response.json(body: {'status': 'ok', 'database': 'connected'});
    }
  } on Exception catch (_) {
    // No devolver excepciones SQL, credenciales ni datos de conexión.
  }

  return Response.json(
    statusCode: HttpStatus.serviceUnavailable,
    body: {'status': 'error', 'database': 'unavailable'},
  );
}
