import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/auth/session_cookie.dart';
import 'package:re_api/http/api_error.dart';
import 'package:test/test.dart';

void main() {
  test('cookie privada exige HTTPS fuera de loopback y no expone dominio', () {
    final token = List.filled(43, 'A').join();
    final until = DateTime.now().toUtc().add(const Duration(days: 7));
    for (final url in [
      'https://api.example.com/auth/login',
      'http://api.example.com/auth/login',
      'https://localhost/auth/login',
    ]) {
      final header = SessionCookie.header(
        Request.post(Uri.parse(url)),
        token: token,
        expiresAt: until,
      );
      expect(header.contains('Secure'), isTrue);
      expect(header.contains('HttpOnly'), isTrue);
      expect(header.contains('SameSite=Strict'), isTrue);
      expect(header.contains('Domain='), isFalse);
    }
    final local = SessionCookie.header(
      Request.post(Uri.parse('http://localhost:8081/auth/login')),
      token: token,
      expiresAt: until,
    );
    expect(local.contains('Secure'), isFalse);
    expect(
      SessionCookie.header(
        Request.post(Uri.parse('http://localhost/auth/logout')),
      ).contains('Max-Age=0'),
      isTrue,
    );
  });
  test(
    'cookie duplicada o mal formada no se acepta; petición simple no renueva',
    () {
      final token = List.filled(43, 'A').join();
      Request request(String cookie) => Request.post(
        Uri.parse('http://localhost/auth/refresh'),
        headers: {'cookie': cookie},
      );
      expect(SessionCookie.read(request('re_refresh=$token')), token);
      expect(
        SessionCookie.read(request('re_refresh=$token; re_refresh=$token')),
        isNull,
      );
      expect(SessionCookie.read(request('re_refresh=bad')), isNull);
      expect(
        () => SessionCookie.validateRequest(request('re_refresh=$token')),
        throwsA(isA<ApiError>()),
      );
    },
  );
}
