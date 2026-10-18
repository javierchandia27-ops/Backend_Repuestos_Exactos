import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:re_api/database/database.dart';
import 'package:test/test.dart';

import '../../../routes/health/database.dart' as route;

class _MockDatabase extends Mock implements Database {}

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late _MockDatabase database;
  late _MockRequestContext context;

  setUp(() {
    database = _MockDatabase();
    context = _MockRequestContext();
    when(() => context.request).thenReturn(
      Request.get(Uri.parse('http://localhost/health/database')),
    );
    when(() => context.read<Database>()).thenReturn(database);
  });

  test('healthy database responds with 200', () async {
    when(database.checkConnection).thenAnswer((_) async => true);
    final response = await route.onRequest(context);
    expect(response.statusCode, HttpStatus.ok);
    expect(jsonDecode(await response.body()), {
      'status': 'ok',
      'database': 'connected',
    });
  });

  test('wrong schema or role responds with 503', () async {
    when(database.checkConnection).thenAnswer((_) async => false);
    final response = await route.onRequest(context);
    expect(response.statusCode, HttpStatus.serviceUnavailable);
  });

  test(
    'connection errors return 503 without exposing internal details',
    () async {
      when(database.checkConnection).thenThrow(
        const SocketException('private-host:5433 sensitive details'),
      );
      final response = await route.onRequest(context);
      expect(response.statusCode, HttpStatus.serviceUnavailable);
      expect(jsonDecode(await response.body()), {
        'status': 'error',
        'database': 'unavailable',
      });
    },
  );

  test('POST is rejected before opening a database connection', () async {
    when(() => context.request).thenReturn(
      Request.post(Uri.parse('http://localhost/health/database')),
    );
    final response = await route.onRequest(context);
    expect(response.statusCode, HttpStatus.methodNotAllowed);
    expect(response.headers['allow'], 'GET');
    verifyNever(database.checkConnection);
  });
}
