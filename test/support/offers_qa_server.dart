import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:re_api/auth/session_store.dart';
import 'package:re_api/config/database_config.dart';
import 'package:re_api/config/ebay_config.dart';
import 'package:re_api/database/database.dart';
import 'package:re_api/features/offers/providers/ebay_provider.dart';
import 'package:re_api/features/offers/services/ebay_tokens.dart';
import 'package:re_api/features/offers/services/offer_service.dart';
import 'package:re_api/features/onboarding/services/google_token_verifier.dart';
import 'package:re_api/features/onboarding/services/onboarding_store.dart';
import 'package:re_api/http/cors_middleware.dart';
import '../../.dart_frog/server.dart' as generated;
import 'qa_offer_provider.dart';

/// Router real y PostgreSQL aislado; rechaza la base normal.
Future<void> main() async {
  if (!(Platform.environment['DB_NAME'] ?? '').startsWith(
    're_api_preflight_',
  )) {
    throw StateError(
      'El servidor de pruebas requiere una base re_api_preflight_.',
    );
  }
  final db = Database(DatabaseConfig.load());
  final client = http.Client();
  final sessions = SessionStore(database: db);
  final google = GoogleTokenVerifier.load();
  final onboarding = OnboardingStore();
  final offers = OfferService(
    QaOfferProvider('mercadolibre'),
    additionalProviders: [
      if (Platform.environment['TEST_EBAY_LIVE'] == 'true')
        EbayProvider(EbayTokens(EbayConfig.load(), client), client)
      else
        QaOfferProvider('ebay'),
    ],
  );
  final handler = generated
      .buildRootHandler()
      .use(provider<OfferService>((_) => offers))
      .use(provider<Database>((_) => db))
      .use(provider<SessionStore>((_) => sessions))
      .use(provider<GoogleTokenVerifier>((_) => google))
      .use(provider<OnboardingStore>((_) => onboarding))
      .use(corsMiddleware({'http://localhost:8080', 'http://127.0.0.1:8080'}));
  final port = int.parse(Platform.environment['QA_SERVER_PORT'] ?? '8084');
  await serve(handler, InternetAddress.loopbackIPv4, port);
  stdout.writeln('QA API lista en $port.');
}
