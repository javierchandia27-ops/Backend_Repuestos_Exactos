import 'package:postgres/postgres.dart';
import 'package:re_api/config/database_config.dart';
import 'package:test/test.dart';

void main() {
  Map<String, String> environment() => {
    'DB_HOST': '127.0.0.1',
    'DB_PORT': '5433',
    'DB_NAME': 'test_database',
    'DB_USER': 'app_backend_user',
    'DB_PASSWORD': 'test-only-secret',
  };

  test('TLS verifies certificates unless explicitly configured otherwise', () {
    expect(
      DatabaseConfig.fromEnvironment(environment()).sslMode,
      SslMode.verifyFull,
    );
  });

  test('missing password fails without exposing configuration values', () {
    final values = environment()..remove('DB_PASSWORD');
    expect(
      () => DatabaseConfig.fromEnvironment(values),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('DB_PASSWORD'),
        ),
      ),
    );
  });

  test('invalid port fails without echoing its value', () {
    for (final invalid in ['0', '65536', 'not-a-port']) {
      final values = environment()..['DB_PORT'] = invalid;
      expect(
        () => DatabaseConfig.fromEnvironment(values),
        throwsFormatException,
      );
    }
  });

  test('unknown TLS mode fails instead of silently disabling TLS', () {
    final values = environment()..['DB_SSL_MODE'] = 'invalid';
    expect(() => DatabaseConfig.fromEnvironment(values), throwsFormatException);
  });
}
