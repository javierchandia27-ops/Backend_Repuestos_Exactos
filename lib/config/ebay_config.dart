import 'dart:io';
import 'package:dotenv/dotenv.dart';

/// Credenciales del servidor y entorno explícito de eBay Browse.
class EbayConfig {
  /// Configura un único entorno y reserva sus credenciales al servidor.
  const EbayConfig({
    this.clientId = '',
    this.clientSecret = '',
    this.environment = 'sandbox',
  });

  /// Carga .env con prioridad para las variables del proceso.
  factory EbayConfig.load() {
    final env = DotEnv(quiet: true)..load();
    String read(String key, String fallback) =>
        (Platform.environment[key] ?? env[key] ?? fallback).trim();
    final environment = read('EBAY_ENVIRONMENT', 'sandbox');
    if (!{'sandbox', 'production'}.contains(environment) ||
        read('EBAY_MARKETPLACE_ID', 'EBAY_US') != 'EBAY_US') {
      throw const FormatException(
        'eBay requiere entorno sandbox/production y marketplace EBAY_US.',
      );
    }
    return EbayConfig(
      clientId: read('EBAY_CLIENT_ID', ''),
      clientSecret: read('EBAY_CLIENT_SECRET', ''),
      environment: environment,
    );
  }

  /// Identidad OAuth privada y entorno explícito del adaptador.
  final String clientId;

  /// Secreto OAuth privado del servidor.
  final String clientSecret;

  /// sandbox o production.
  final String environment;

  /// Indica si ambas credenciales están presentes.
  bool get configured => clientId.isNotEmpty && clientSecret.isNotEmpty;

  /// Host fijo oficial, sin aceptar URLs de configuración o del cliente.
  String get apiHost => switch (environment) {
    'sandbox' => 'api.sandbox.ebay.com',
    'production' => 'api.ebay.com',
    _ => throw const FormatException('Entorno eBay inválido.'),
  };
}
