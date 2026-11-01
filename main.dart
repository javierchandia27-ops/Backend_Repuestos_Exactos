import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/config/database_config.dart';
import 'package:re_api/config/mercadolibre_config.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/features/offers/providers/mercadolibre_provider.dart';
import 'package:re_api/features/offers/services/mercadolibre_tokens.dart';
import 'package:re_api/features/offers/services/offer_service.dart';
import 'package:re_api/features/onboarding/services/google_token_verifier.dart';
import 'package:re_api/features/onboarding/services/onboarding_store.dart';
import 'package:re_api/http/cors_middleware.dart';

late final GoogleTokenVerifier _google;
late final OnboardingStore _onboarding;
late final Database _database;
late final SessionStore _sessions;
late final Set<String> _corsOrigins;
late final OfferService _offers;

// Dart Frog ejecuta init una sola vez al iniciar el proceso.
Future<void> init(InternetAddress ip, int port) async {
  _database = Database(DatabaseConfig.load());
  _sessions = SessionStore(database: _database);
  _google = GoogleTokenVerifier.load();
  _onboarding = OnboardingStore();
  _corsOrigins = loadCorsOrigins();
  final client = http.Client();
  _offers = OfferService(
    MercadoLibreProvider(
      MercadoLibreTokens(MercadoLibreConfig.load(), client),
      client,
    ),
  );
}

Future<HttpServer> run(Handler handler, InternetAddress ip, int port) {
  return serve(
    handler
        .use(provider<OfferService>((context) => _offers))
        .use(provider<GoogleTokenVerifier>((context) => _google))
        .use(provider<OnboardingStore>((context) => _onboarding))
        .use(provider<Database>((context) => _database))
        .use(provider<SessionStore>((context) => _sessions))
        .use(corsMiddleware(_corsOrigins)),
    ip,
    port,
  );
}
