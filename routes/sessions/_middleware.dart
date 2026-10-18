import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/features/diagnostics/repositories/diagnostic_repository.dart';
import 'package:re_api/features/diagnostics/services/diagnostic_service.dart';

Handler middleware(Handler handler) => handler.use(
  provider<DiagnosticService>(
    (context) => DiagnosticService(
      DiagnosticRepository(context.read<TxSession>()),
    ),
  ),
);
