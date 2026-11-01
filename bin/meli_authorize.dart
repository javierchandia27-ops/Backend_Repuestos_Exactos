import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:re_api/config/mercadolibre_config.dart';
import 'package:re_api/features/offers/providers/mercadolibre_http.dart';
import 'package:re_api/features/offers/services/mercadolibre_tokens.dart';
import 'package:re_api/http/api_error.dart';

String randomToken() => base64Url
    .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');
bool sameState(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Autorización del operador, fuera del frontend y de los endpoints públicos de
/// la API.
Future<void> main(List<String> args) async {
  final config = MercadoLibreConfig.load();
  if (!config.configured) {
    stderr.writeln('Configura MELI_CLIENT_ID y MELI_CLIENT_SECRET en .env.');
    exitCode = 1;
    return;
  }
  final env = DotEnv(quiet: true)..load();
  final tunnelIndex = args.indexOf('--tunnel');
  Process? tunnel;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8094);
  final client = http.Client();
  StreamSubscription<String>? tunnelOutput;
  try {
    String redirect;
    if (tunnelIndex >= 0 && args.length > tunnelIndex + 1) {
      tunnel = await Process.start(args[tunnelIndex + 1], [
        'tunnel',
        '--url',
        'http://127.0.0.1:8094',
        '--protocol',
        'http2',
        '--no-autoupdate',
      ]);
      final origin = Completer<String>();
      unawaited(tunnel.stdout.drain<void>());
      tunnelOutput = tunnel.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final match = RegExp(
              r'https://[a-z0-9-]+\.trycloudflare\.com',
            ).firstMatch(line);
            if (match != null && !origin.isCompleted) {
              origin.complete(match.group(0)!);
            }
          });
      redirect =
          '${await origin.future.timeout(const Duration(seconds: 40))}/integrations/mercadolibre/callback';
      stdout
        ..writeln(
          'Registra exactamente este Redirect URI en tu '
          'aplicación de Mercado Libre:\n$redirect',
        )
        ..writeln('Cuando esté guardado, presiona Enter aquí.');
      stdin.readLineSync();
    } else {
      redirect =
          Platform.environment['MELI_REDIRECT_URI'] ??
          env['MELI_REDIRECT_URI'] ??
          '';
    }
    final uri = Uri.tryParse(redirect);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/integrations/mercadolibre/callback') {
      throw const ApiError(400, 'invalid_meli_redirect_uri');
    }
    final state = randomToken();
    final verifier = randomToken();
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    final authorize = Uri.https('auth.mercadolibre.cl', '/authorization', {
      'response_type': 'code',
      'client_id': config.clientId,
      'redirect_uri': redirect,
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });
    stdout.writeln(
      'Abre esta dirección para autorizar la cuenta '
      '(vence en 15 minutos):\n$authorize',
    );
    final deadline = DateTime.now().add(const Duration(minutes: 15));
    final timeout = Timer(
      const Duration(minutes: 15),
      () => server.close(force: true),
    );
    try {
      await for (final request in server) {
        request.response.headers.set('cache-control', 'no-store');
        request.response.headers.set('referrer-policy', 'no-referrer');
        request.response.headers.set(
          'content-security-policy',
          "default-src 'none'; frame-ancestors 'none'",
        );
        if (request.method != 'GET' || request.uri.path != uri.path) {
          request.response.statusCode = 404;
          await request.response.close();
          continue;
        }
        final query = request.uri.queryParameters;
        if (DateTime.now().isAfter(deadline) ||
            !sameState(query['state'] ?? '', state) ||
            request.uri.queryParametersAll.values.any((v) => v.length != 1)) {
          request.response.statusCode = 400;
          request.response.write('Autorizacion invalida o vencida.');
          await request.response.close();
          continue;
        }
        if (query['error'] != null) {
          request.response.statusCode = 400;
          request.response.write('Autorizacion cancelada.');
          await request.response.close();
          break;
        }
        final code = query['code'];
        if (code == null || code.isEmpty || code.length > 2048) {
          request.response.statusCode = 400;
          await request.response.close();
          continue;
        }
        try {
          final res = await mercadoLibreRequest(
            client,
            'POST',
            Uri.https('api.mercadolibre.com', '/oauth/token'),
            fields: {
              'grant_type': 'authorization_code',
              'client_id': config.clientId,
              'client_secret': config.clientSecret,
              'code': code,
              'redirect_uri': redirect,
              'code_verifier': verifier,
            },
          );
          if (res.statusCode != 200) {
            throw const ApiError(502, 'oauth_exchange_failed');
          }
          await MercadoLibreTokens.storeTokenResponse(config, res.body);
          request.response.write(
            'Cuenta autorizada. Puedes cerrar esta ventana.',
          );
          stdout.writeln(
            'Tokens guardados de forma privada. Ya '
            'puedes probar la busqueda desde la aplicacion.',
          );
        } on ApiError catch (e) {
          request.response.statusCode = 502;
          request.response.write(
            'No se pudo completar la autorizacion. Revisa la terminal.',
          );
          stderr.writeln(e.code);
          exitCode = 1;
        }
        await request.response.close();
        break;
      }
    } finally {
      timeout.cancel();
    }
  } on ApiError catch (e) {
    stderr.writeln(e.code);
    exitCode = 1;
  } on TimeoutException {
    stderr.writeln('El tunel no estuvo disponible a tiempo.');
    exitCode = 1;
  } finally {
    client.close();
    await server.close(force: true);
    await tunnelOutput?.cancel();
    tunnel?.kill();
  }
}
