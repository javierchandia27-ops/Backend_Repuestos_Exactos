import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/auth/login_credentials.dart';
import 'package:re_api/http/api_error.dart';
import 'package:test/test.dart';

Request request(Object? body, {String type = 'application/json'}) =>
    Request.post(
      Uri.parse('http://localhost/auth/login'),
      headers: {'content-type': type},
      body: jsonEncode(body),
    );
Matcher status(int code) => throwsA(
  isA<ApiError>().having((error) => error.statusCode, 'status', code),
);

void main() {
  test('normalizes email without trimming or modifying password', () async {
    final credentials = await LoginCredentials.read(
      request({
        'email': ' ADMIN@EXAMPLE.COM ',
        'password': ' spaces remain ',
      }),
    );
    expect(credentials.email, 'admin@example.com');
    expect(credentials.password, ' spaces remain ');
  });

  test('requires JSON content type', () async {
    await expectLater(
      LoginCredentials.read(request({}, type: 'text/plain')),
      status(415),
    );
  });

  test('malformed JSON returns a controlled error', () async {
    final invalid = Request.post(
      Uri.parse('http://localhost/auth/login'),
      headers: {'content-type': 'application/json'},
      body: '{',
    );
    await expectLater(LoginCredentials.read(invalid), status(400));
  });

  test(
    'rejects arrays, missing fields, wrong types and client identity',
    () async {
      for (final body in [
        <Object?>[],
        <String, Object?>{},
        {'email': 'a@b.com', 'password': 42},
        {'email': 'a@b.com', 'password': 'test-password', 'rol': 'admin'},
        {'email': 'a@b.com', 'password': 'test-password', 'taller_id': 2},
      ]) {
        await expectLater(LoginCredentials.read(request(body)), status(400));
      }
    },
  );

  test(
    'rejects invalid emails and passwords beyond bcrypt byte limit',
    () async {
      for (final body in [
        {'email': 'not-an-email', 'password': 'test-password'},
        {'email': 'a b@c.com', 'password': 'test-password'},
        {'email': 'a@b.com', 'password': List.filled(37, 'ñ').join()},
      ]) {
        await expectLater(LoginCredentials.read(request(body)), status(400));
      }
    },
  );

  test('limits body size even when content length is missing', () async {
    await expectLater(
      LoginCredentials.read(
        request({
          'email': 'a@b.com',
          'password': List.filled(5000, 'x').join(),
        }),
      ),
      status(413),
    );
  });
}
