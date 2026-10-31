import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/config/database_config.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/features/onboarding/services/google_token_verifier.dart';
import 'package:re_api/features/onboarding/services/onboarding_store.dart';
import 'package:re_api/http/cors_middleware.dart';

late final GoogleTokenVerifier _google;
late final OnboardingStore _onboarding;
late final Database _database;
late final SessionStore _sessions;
late final Set<String> _corsOrigins;

// Dart Frog ejecuta init una sola vez al iniciar el proceso.
Future<void> init(InternetAddress ip, int port) async {
  _database = Database(DatabaseConfig.load());
  _sessions = SessionStore();
  _google = GoogleTokenVerifier.load();
  _onboarding = OnboardingStore();
  _corsOrigins = loadCorsOrigins();
}

Future<HttpServer> run(Handler handler, InternetAddress ip, int port) {
  return serve(
    handler
        .use(provider<GoogleTokenVerifier>((context) => _google))
        .use(provider<OnboardingStore>((context) => _onboarding))
        .use(provider<Database>((context) => _database))
        .use(provider<SessionStore>((context) => _sessions))
        .use(corsMiddleware(_corsOrigins)),
    ip,
    port,
  );
}
