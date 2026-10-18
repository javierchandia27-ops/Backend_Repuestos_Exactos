import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

/// Configuración del servidor; nunca se envía al cliente.
class DatabaseConfig {
  /// Valida las variables requeridas sin incluir valores en los errores.
  DatabaseConfig.fromEnvironment(Map<String, String> environment)
    : host = _required(environment, 'DB_HOST'),
      port = _port(environment),
      database = _required(environment, 'DB_NAME'),
      username = _required(environment, 'DB_USER'),
      password = _required(environment, 'DB_PASSWORD'),
      sslMode = _sslMode(environment);

  /// Lee .env; las variables del proceso tienen prioridad.
  factory DatabaseConfig.load() {
    final dotenv = DotEnv(quiet: true)..load();
    // Las variables del proceso prevalecen sobre el archivo local.
    return DatabaseConfig.fromEnvironment({
      for (final key in [
        'DB_HOST',
        'DB_PORT',
        'DB_NAME',
        'DB_USER',
        'DB_PASSWORD',
        'DB_SSL_MODE',
      ])
        if (Platform.environment[key] != null || dotenv[key] != null)
          key: Platform.environment[key] ?? dotenv[key]!,
    });
  }

  /// Servidor PostgreSQL.
  final String host;

  /// Puerto del servidor.
  final int port;

  /// Nombre de la base de datos.
  final String database;

  /// Usuario de conexión de la aplicación.
  final String username;

  /// Credencial privada del servidor.
  final String password;

  /// Modo TLS de la conexión.
  final SslMode sslMode;

  /// Parámetros de conexión para el controlador PostgreSQL.
  Endpoint get endpoint => Endpoint(
    host: host,
    port: port,
    database: database,
    username: username,
    password: password,
  );

  static String _required(Map<String, String> environment, String key) {
    final value = environment[key];
    if (value == null || value.trim().isEmpty) {
      throw FormatException('Falta configurar $key en el entorno del backend.');
    }
    return value;
  }

  static int _port(Map<String, String> environment) {
    final port = int.tryParse(_required(environment, 'DB_PORT'));
    if (port == null || port < 1 || port > 65535) {
      throw const FormatException('DB_PORT debe estar entre 1 y 65535.');
    }
    return port;
  }

  static SslMode _sslMode(Map<String, String> environment) {
    return switch (environment['DB_SSL_MODE'] ?? 'verify-full') {
      'disable' => SslMode.disable,
      'require' => SslMode.require,
      'verify-full' => SslMode.verifyFull,
      _ => throw const FormatException(
        'DB_SSL_MODE debe ser disable, require o verify-full.',
      ),
    };
  }
}
