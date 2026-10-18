import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:test/test.dart';

const identity = AuthIdentity(
  userId: 1,
  workshopId: 2,
  userPublicId: '11111111-1111-4111-8111-111111111111',
  workshopPublicId: '22222222-2222-4222-8222-222222222222',
  role: UserRole.mecanico,
  name: 'Test User',
);

void main() {
  test(
    'opaque tokens are distinct and reference only server-side identity',
    () {
      final store = SessionStore();
      final first = store.issue(identity);
      final second = store.issue(identity);
      expect(first.token.length, 43);
      expect(first.token == second.token, isFalse);
      expect(store.resolve(first.token)?.identity, same(identity));
      expect(first.token.contains(identity.workshopPublicId), isFalse);
      expect(
        identity.toPublicJson().keys,
        unorderedEquals(['usuario', 'taller']),
      );
    },
  );

  test('session expires at the absolute boundary without sliding renewal', () {
    var now = DateTime.utc(2026);
    final store = SessionStore(clock: () => now);
    final issued = store.issue(identity);
    now = now.add(const Duration(minutes: 59));
    expect(store.resolve(issued.token), isNotNull);
    now = now.add(const Duration(minutes: 1));
    expect(store.resolve(issued.token), isNull);
  });

  test('logout revokes immediately and survives repeated revocation', () {
    final store = SessionStore();
    final issued = store.issue(identity);
    store
      ..revoke(issued.token)
      ..revoke(issued.token);
    expect(store.resolve(issued.token), isNull);
  });

  test('capacity rejects new sessions and recovers after expiration', () {
    var now = DateTime.utc(2026);
    final store = SessionStore(maxSessions: 1, clock: () => now);
    final first = store.issue(identity);
    expect(() => store.issue(identity), throwsA(isA<SessionLimitException>()));
    expect(store.resolve(first.token), isNotNull);
    now = now.add(const Duration(hours: 1));
    expect(store.issue(identity).session.expiresAt.isAfter(now), isTrue);
  });

  test(
    'malformed tokens and sessions from a previous process are rejected',
    () {
      final issued = SessionStore().issue(identity);
      final freshStore = SessionStore();
      for (final token in ['', 'invalid', 'a.b.c', issued.token]) {
        expect(freshStore.resolve(token), isNull);
      }
    },
  );
}
