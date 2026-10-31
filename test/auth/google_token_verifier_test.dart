import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jose/jose.dart';
import 'package:re_api/features/onboarding/services/google_token_verifier.dart';
import 'package:re_api/http/api_error.dart';
import 'package:test/test.dart';

void main() {
  final generated = JsonWebKey.generate('RS256', keyBitLength: 2048);
  final key = JsonWebKey.fromJson({...generated.toJson(), 'kid': 'test-key'});
  final other = JsonWebKey.fromJson({
    ...JsonWebKey.generate('RS256', keyBitLength: 2048).toJson(),
    'kid': 'test-key',
  });
  final now = DateTime.utc(2026, 10, 31, 12);
  const audience = 'test.apps.googleusercontent.com';
  var fetches = 0;
  late GoogleTokenVerifier verifier;
  setUp(() {
    fetches = 0;
    verifier = GoogleTokenVerifier(
      {audience},
      clock: () => now,
      client: MockClient((_) async {
        fetches++;
        return http.Response(
          jsonEncode({
            'keys': [
              {
                'kty': 'RSA',
                'kid': 'test-key',
                'alg': 'RS256',
                'use': 'sig',
                'n': key['n'],
                'e': key['e'],
              },
            ],
          }),
          200,
          headers: {'cache-control': 'public, max-age=3600'},
        );
      }),
    );
  });
  tearDown(() => verifier.close());
  String sign({Map<String, dynamic> overrides = const {}, JsonWebKey? signer}) {
    final builder = JsonWebSignatureBuilder()
      ..jsonContent = {
        'iss': 'https://accounts.google.com',
        'aud': audience,
        'sub': 'stable-subject',
        'iat': now.millisecondsSinceEpoch ~/ 1000,
        'exp': now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
        'nonce': 'test-nonce',
        'email': 'owner@gmail.com',
        'email_verified': true,
        'name': 'Dueño',
        ...overrides,
      }
      ..addRecipient(signer ?? key, algorithm: 'RS256');
    return builder.build().toCompactSerialization();
  }

  Matcher errorCode(String code) =>
      isA<ApiError>().having((e) => e.code, 'code', code);
  test('firma, claims y caché de claves', () async {
    final identity = await verifier.verify(sign(), 'test-nonce');
    expect(identity.subject, 'stable-subject');
    expect(identity.authoritativeEmail, isTrue);
    await verifier.verify(sign(), 'test-nonce');
    expect(fetches, 1);
  });
  for (final entry in <String, Map<String, dynamic>>{
    'audiencia ajena': {'aud': 'attacker.apps.googleusercontent.com'},
    'emisor ajeno': {'iss': 'https://attacker.test'},
    'expirado': {
      'exp':
          now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch ~/
          1000,
    },
    'nonce ajeno': {'nonce': 'another'},
    'correo no verificado': {'email_verified': false},
    'sin sujeto': {'sub': null},
    'fecha futura': {
      'iat': now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
    },
  }.entries) {
    test('rechaza ${entry.key}', () async {
      await expectLater(
        verifier.verify(sign(overrides: entry.value), 'test-nonce'),
        throwsA(errorCode('invalid_google_token')),
      );
    });
  }
  test('rechaza firma diferente y algoritmo none', () async {
    await expectLater(
      verifier.verify(sign(signer: other), 'test-nonce'),
      throwsA(errorCode('invalid_google_token')),
    );
    final token =
        '${base64Url.encode(utf8.encode(jsonEncode({'alg': 'none'})))}.e30.';
    await expectLater(
      verifier.verify(token, 'test-nonce'),
      throwsA(errorCode('invalid_google_token')),
    );
  });
  test('correo externo no permite alta automática', () async {
    final identity = await verifier.verify(
      sign(overrides: {'email': 'person@example.test'}),
      'test-nonce',
    );
    expect(identity.authoritativeEmail, isFalse);
  });
  test('sin credenciales falla cerrado', () async {
    final disabled = GoogleTokenVerifier({});
    addTearDown(disabled.close);
    await expectLater(
      disabled.verify(sign(), 'test-nonce'),
      throwsA(errorCode('google_not_configured')),
    );
  });
}
