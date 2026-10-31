/// Identidad obtenida únicamente tras validar la firma y los claims de Google.
class GoogleIdentity {
  /// Construye una identidad verificada por el servidor.
  const GoogleIdentity({
    required this.subject,
    required this.email,
    required this.name,
    required this.authoritativeEmail,
  });

  /// Identificador estable de Google.
  final String subject;

  /// Correo normalizado del token verificado.
  final String email;

  /// Nombre de presentación validado.
  final String name;

  /// Google administra este correo Gmail o Workspace.
  final bool authoritativeEmail;
}
