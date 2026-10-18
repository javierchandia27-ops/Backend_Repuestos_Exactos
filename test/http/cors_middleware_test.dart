import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:re_api/http/cors_middleware.dart';
import 'package:test/test.dart';

class _Context extends Mock implements RequestContext {}

void main() {
  Future<Response> call(Request request, {void Function()? reached}) {
    final context = _Context();
    when(() => context.request).thenReturn(request);
    return Future.value(
      corsMiddleware({'http://localhost:8080'})((_) {
        reached?.call();
        return Response.json(
          statusCode: 401,
          body: {'error': 'invalid_session'},
        );
      })(context),
    );
  }

  final url = Uri.parse('http://localhost:8081/settings');

  test('allowed origins receive CORS headers even on auth failures', () async {
    final response = await call(
      Request.get(url, headers: {'origin': 'http://localhost:8080'}),
    );
    expect(response.statusCode, 401);
    expect(
      response.headers['access-control-allow-origin'],
      'http://localhost:8080',
    );
    expect(response.headers['vary'], 'Origin');
  });

  test(
    'preflight does not reach authentication or database handlers',
    () async {
      var reached = false;
      final response = await call(
        Request(
          'OPTIONS',
          url,
          headers: {
            'origin': 'http://localhost:8080',
            'access-control-request-method': 'GET',
            'access-control-request-headers': 'authorization,content-type',
          },
        ),
        reached: () => reached = true,
      );
      expect(response.statusCode, 204);
      expect(reached, isFalse);
    },
  );

  test('unlisted origins cannot access the API through the browser', () async {
    var reached = false;
    final response = await call(
      Request.get(url, headers: {'origin': 'https://unlisted.example'}),
      reached: () => reached = true,
    );
    expect(response.statusCode, 403);
    expect(
      response.headers.containsKey('access-control-allow-origin'),
      isFalse,
    );
    expect(reached, isFalse);
  });

  test('unsupported preflight headers are rejected', () async {
    final response = await call(
      Request(
        'OPTIONS',
        url,
        headers: {
          'origin': 'http://localhost:8080',
          'access-control-request-method': 'POST',
          'access-control-request-headers': 'x-taller-id',
        },
      ),
    );
    expect(response.statusCode, 403);
  });

  test('native clients do not need an Origin header', () async {
    final response = await call(Request.get(url));
    expect(response.statusCode, 401);
    expect(
      response.headers.containsKey('access-control-allow-origin'),
      isFalse,
    );
  });
}
