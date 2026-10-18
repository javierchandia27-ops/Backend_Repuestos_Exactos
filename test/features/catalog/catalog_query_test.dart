import 'package:re_api/features/catalog/dto/part_search_query.dart';
import 'package:re_api/http/api_error.dart';
import 'package:re_api/http/query_validation.dart';
import 'package:test/test.dart';

void main() {
  test('DTC normalization accepts only complete codes or valid prefixes', () {
    expect(diagnosticCode(' p0300 '), 'P0300');
    for (final value in ['', 'P', 'P0', 'P03', 'P0300', 'b1a']) {
      expect(diagnosticCode(value, prefix: true), value.toUpperCase());
    }
    for (final value in ['P4', 'X0300', 'P0%', 'P03_', "P03'", 'P03000']) {
      expect(
        () => diagnosticCode(value, prefix: true),
        throwsA(isA<ApiError>()),
      );
    }
  });
  test('compatibility requires a model for a year and bounds pagination', () {
    PartSearchQuery parse(String query) =>
        PartSearchQuery.parse(Uri.parse('http://localhost/parts?$query'));
    final query = parse(
      'model=00000000-0000-0000-0000-000000000001&year=2018&limit=2&offset=2',
    );
    expect(query.year, 2018);
    expect(query.offset, 2);
    for (final value in [
      'year=2018',
      'model=bad',
      'limit=101',
      'offset=-1',
      'limit=1&limit=2',
      'taller_id=2',
      'year=2101',
      'model=',
      'offset=1000001',
    ]) {
      expect(() => parse(value), throwsA(isA<ApiError>()));
    }
  });
}
