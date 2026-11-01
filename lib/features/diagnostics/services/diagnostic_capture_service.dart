import 'package:re_api/auth/auth_identity.dart';
import 'package:re_api/features/diagnostics/dto/create_scan_request.dart';
import 'package:re_api/features/diagnostics/repositories/diagnostic_capture_repository.dart';

/// Caso de uso de persistencia de una captura ya terminada; no espera
/// Bluetooth.
class DiagnosticCaptureService {
  /// Repositorio de la transacción autenticada.
  DiagnosticCaptureService(this.repository);

  /// Persistencia de sesiones y observaciones.
  final DiagnosticCaptureRepository repository;

  /// Resuelve idempotencia y devuelve el detalle persistido.
  Future<Map<String, Object?>> save(
    CreateScanRequest input,
    AuthIdentity user,
  ) async => repository.detail(await repository.create(input, user));
}
