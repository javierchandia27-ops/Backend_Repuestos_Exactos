import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(
      statusCode: HttpStatus.methodNotAllowed,
      headers: {'allow': 'GET'},
    );
  }
  // q_configuracion de RE-db: RLS decide el taller, sin filtro del cliente.
  final result = await context.read<TxSession>().execute('''
    SELECT t.id_publico, t.nombre, tc.moneda, tc.tema::text AS tema, tc.margen_pct,
           tc.retencion_anios, tc.actualizado_en
    FROM public.taller t
    JOIN public.taller_configuracion tc ON tc.taller_id = t.id
  ''');
  if (result.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'error': 'not_found'},
    );
  }
  final values = result.single.toColumnMap();
  return Response.json(
    body: {
      for (final entry in values.entries)
        entry.key: entry.value is DateTime
            ? (entry.value! as DateTime).toUtc().toIso8601String()
            : entry.value,
    },
  );
}
