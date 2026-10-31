import 'dart:async';
import 'package:re_api/features/onboarding/models/google_identity.dart';
import 'package:re_api/features/onboarding/services/onboarding_store.dart';
import 'package:re_api/http/api_error.dart';
import 'package:test/test.dart';

void main() {
  const identity = GoogleIdentity(
    subject: 'sub',
    email: 'owner@gmail.com',
    name: 'Dueño',
    authoritativeEmail: true,
  );
  test('desafío único y con vencimiento', () {
    var now = DateTime.utc(2026);
    final store = OnboardingStore(clock: () => now);
    final nonce = store.challenge();
    store.consumeChallenge(nonce);
    expect(() => store.consumeChallenge(nonce), throwsA(isA<ApiError>()));
    final expired = store.challenge();
    now = now.add(const Duration(minutes: 11));
    expect(() => store.consumeChallenge(expired), throwsA(isA<ApiError>()));
  });
  test('ticket no permite aceptación concurrente ni reutilización', () async {
    final store = OnboardingStore();
    final token = store.issue(identity);
    final gate = Completer<int>();
    final first = store.use(token, (_) => gate.future);
    await expectLater(
      store.use(token, (_) async => 2),
      throwsA(isA<ApiError>()),
    );
    gate.complete(1);
    expect(await first, 1);
    await expectLater(
      store.use(token, (_) async => 3),
      throwsA(isA<ApiError>()),
    );
  });
  test('un fallo permite reintentar sin ampliar vencimiento', () async {
    var now = DateTime.utc(2026);
    final store = OnboardingStore(clock: () => now);
    final token = store.issue(identity);
    await expectLater(
      store.use<void>(
        token,
        (_) async => throw const ApiError(409, 'invalid_invitation'),
      ),
      throwsA(isA<ApiError>()),
    );
    expect(await store.use(token, (_) async => true), isTrue);
    final expired = store.issue(identity);
    now = now.add(const Duration(minutes: 11));
    await expectLater(
      store.use(expired, (_) async => true),
      throwsA(isA<ApiError>()),
    );
  });
  test('limita solicitudes por origen', () {
    final store = OnboardingStore();
    for (var i = 0; i < 30; i++) {
      store.rateLimit('127.0.0.1');
    }
    expect(
      () => store.rateLimit('127.0.0.1'),
      throwsA(isA<ApiError>().having((e) => e.statusCode, 'status', 429)),
    );
  });
}
