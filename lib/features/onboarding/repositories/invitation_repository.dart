import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/http/api_error.dart';

/// Invitaciones del taller limitadas por contexto y RLS.
class InvitationRepository {
  /// Recibe la transacción autenticada del propietario.
  const InvitationRepository(this.tx);

  /// Transacción con rol y contexto local de taller.
  final TxSession tx;
  static const _columns = '''
    id_publico, email, rol::text, creado_en::text, vence_en::text,
    CASE WHEN aceptada_en IS NOT NULL THEN 'accepted'
         WHEN revocada_en IS NOT NULL THEN 'revoked'
         WHEN vence_en<=now() THEN 'expired'
         ELSE 'pending' END AS status
  ''';

  /// Lista invitaciones sin hashes ni enlaces privados.
  Future<List<Map<String, dynamic>>> list() async {
    final rows = await tx.execute('''
      SELECT $_columns FROM public.invitacion_taller
      ORDER BY creado_en DESC LIMIT 100
    ''');
    return rows.map((r) => r.toColumnMap()).toList();
  }

  /// Entrega un enlace una sola vez y guarda su hash.
  Future<Map<String, dynamic>> create(String email) async {
    // Orden fijo: taller y después correo, compartido con la aceptación.
    await tx.execute('''
      SELECT pg_advisory_xact_lock(hashtextextended(
        'invitations:' || public.fn_contexto_taller_id()::text, 12))
    ''');
    await tx.execute(
      Sql.named('SELECT pg_advisory_xact_lock(hashtextextended(@email, 11))'),
      parameters: {'email': email},
    );
    final member = await tx.execute(
      Sql.named('SELECT id_publico FROM public.usuario WHERE email=@email'),
      parameters: {'email': email},
    );
    if (member.isNotEmpty) {
      throw const ApiError(409, 'already_member');
    }
    final pending = await tx.execute(
      Sql.named('''
        SELECT count(*) FROM public.invitacion_taller
        WHERE aceptada_en IS NULL AND revocada_en IS NULL
          AND vence_en>now() AND email<>@email
      '''),
      parameters: {'email': email},
    );
    if ((pending.single[0]! as int) >= 100) {
      throw const ApiError(429, 'invitation_limit');
    }
    // Regenerar revoca el enlace anterior, incluso si ya había vencido.
    await tx.execute(
      Sql.named('''
        UPDATE public.invitacion_taller SET revocada_en=now()
        WHERE email=@email AND aceptada_en IS NULL AND revocada_en IS NULL
      '''),
      parameters: {'email': email},
    );
    final random = Random.secure();
    final token = base64UrlEncode(
      List.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    final hash = sha256.convert(utf8.encode(token)).toString();
    final rows = await tx.execute(
      Sql.named('''
        INSERT INTO public.invitacion_taller
          (taller_id,email,rol,token_hash,invitado_por)
        VALUES(public.fn_contexto_taller_id(),@email,
          'mecanico'::public.tipo_rol_usuario,@hash,public.fn_contexto_usuario_id())
        RETURNING $_columns
      '''),
      parameters: {'email': email, 'hash': hash},
    );
    final env = DotEnv(quiet: true)..load();
    final origin =
        Platform.environment['FRONTEND_URL'] ??
        env['FRONTEND_URL'] ??
        'http://localhost:8080';
    final uri = Uri.tryParse(origin);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                {'localhost', '127.0.0.1'}.contains(uri.host)))) {
      throw const ApiError(503, 'invalid_frontend_url');
    }
    return {
      ...rows.single.toColumnMap(),
      'invitation_url': '${uri.origin}/#/login?invitation=$token',
    };
  }

  /// Invalida una invitación pendiente visible en este taller.
  Future<bool> revoke(String id) async {
    final rows = await tx.execute(
      Sql.named('''
        UPDATE public.invitacion_taller SET revocada_en=now()
        WHERE id_publico=@id::uuid AND aceptada_en IS NULL
          AND revocada_en IS NULL RETURNING id_publico
      '''),
      parameters: {'id': id},
    );
    return rows.isNotEmpty;
  }
}
