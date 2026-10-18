import 'dart:convert';

import 'package:re_api/features/diagnostics/dto/history_query.dart';
import 'package:re_api/features/diagnostics/models/history_cursor.dart';
import 'package:re_api/features/diagnostics/models/session_status.dart';
import 'package:re_api/http/api_error.dart';
import 'package:test/test.dart';

void main() {
  HistoryQuery parse(String query) =>
      HistoryQuery.parse(Uri.parse('http://localhost/sessions$query'));

  test('defaults and filters are bounded and typed', () {
    expect(parse('').limit, 20);
    final query = parse('?limit=100&status=cotizado');
    expect(query.limit, 100);
    expect(query.status, SessionStatus.cotizado);
  });

  test('rejects unknown, duplicated, empty and hostile parameters', () {
    for (final query in [
      '?limit=0',
      '?limit=101',
      '?limit=-1',
      '?limit=1.5',
      '?limit=',
      '?limit=2&limit=3',
      '?status=',
      '?status=unknown',
      '?status=pendiente%27%3BDROP',
      '?taller_id=2',
      '?rol=admin',
      '?limit=%202',
    ]) {
      expect(() => parse(query), throwsA(isA<ApiError>()), reason: query);
    }
  });

  test('cursor preserves microseconds and only public identity', () {
    final cursor = HistoryCursor(
      startedAt: DateTime.parse('2026-10-18T12:00:00.123456Z'),
      publicId: '00000000-0000-0000-0000-000000000001',
    );
    final encoded = HistoryQuery.encodeCursor(cursor);
    final decoded = HistoryQuery.decodeCursor(encoded);
    expect(decoded.startedAt, cursor.startedAt);
    expect(decoded.publicId, cursor.publicId);
    final json =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(encoded))))
            as Map;
    expect(json.keys, unorderedEquals(['date', 'id']));
  });

  test('rejects malformed, oversized and noncanonical cursors', () {
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    for (final cursor in [
      '',
      '!',
      'a' * 513,
      encode([]),
      encode({'date': 1, 'id': 2}),
      encode({
        'date': '2026-02-30T00:00:00.000Z',
        'id': '00000000-0000-0000-0000-000000000001',
      }),
      encode({'date': '2026-10-18T00:00:00.000Z', 'id': 'bad-id'}),
      encode({
        'date': '2026-10-18T00:00:00.000Z',
        'id': '00000000-0000-0000-0000-000000000001',
        'internal_id': 3,
      }),
    ]) {
      expect(() => HistoryQuery.decodeCursor(cursor), throwsA(isA<ApiError>()));
    }
  });
}
