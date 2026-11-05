import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:re_api/config/ebay_config.dart';
import 'package:re_api/features/offers/providers/ebay_provider.dart';
import 'package:re_api/features/offers/services/ebay_tokens.dart';
import 'package:re_api/http/api_error.dart';

/// Prueba de lectura contra el entorno configurado, sin imprimir credenciales.
Future<void> main(List<String> args) async {
  final client = http.Client();
  try {
    final config = EbayConfig.load();
    final tokens = EbayTokens(config, client);
    await tokens.accessToken();
    final offers = await EbayProvider(
      tokens,
      client,
    ).search(args.isEmpty ? 'spark plug' : args.single);
    stdout.writeln(
      jsonEncode({
        'status': 'ok',
        'provider': 'ebay',
        'environment': config.environment,
        'marketplace': 'EBAY_US',
        'token_received': true,
        'items': offers.length,
        'currencies': offers.map((o) => o.currency).toSet().toList(),
      }),
    );
  } on ApiError catch (e) {
    stderr.writeln(jsonEncode({'status': 'error', 'error': e.code}));
    exitCode = 1;
  } on FormatException {
    stderr.writeln('Configuración o argumentos eBay inválidos.');
    exitCode = 1;
  } finally {
    client.close();
  }
}
