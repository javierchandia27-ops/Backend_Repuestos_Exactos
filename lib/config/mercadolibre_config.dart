import 'dart:io';
import 'package:dotenv/dotenv.dart';

/// Configuración privada de Mercado Libre y ubicación de tokens rotatorios.
class MercadoLibreConfig {
  /// Configuración privada de Mercado Libre y ubicación de tokens rotatorios.
  const MercadoLibreConfig({
    this.clientId = '',
    this.clientSecret = '',
    this.tokenFile = '.secrets/mercadolibre-tokens.json',
  });

  /// Lee .env con prioridad para las variables del proceso.
  factory MercadoLibreConfig.load() {
    final env = DotEnv(quiet: true)..load();
    String get(String k, String fallback) =>
        Platform.environment[k] ?? env[k] ?? fallback;
    return MercadoLibreConfig(
      clientId: get('MELI_CLIENT_ID', '').trim(),
      clientSecret: get('MELI_CLIENT_SECRET', '').trim(),
      tokenFile: get('MELI_TOKEN_FILE', '.secrets/mercadolibre-tokens.json'),
    );
  }

  /// Identificador OAuth de la aplicación de Mercado Libre.
  final String clientId;

  /// Secreto OAuth, reservado al servidor.
  final String clientSecret;

  /// Archivo privado de tokens; debe quedar fuera de Git.
  final String tokenFile;

  /// Indica si se definieron ambas credenciales OAuth.
  bool get configured => clientId.isNotEmpty && clientSecret.isNotEmpty;
}
