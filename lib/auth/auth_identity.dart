/// Roles permitidos por el contrato de RE-db.
enum UserRole {
  /// Administración del taller.
  admin,

  /// Operación mecánica.
  mecanico,

  /// Consulta y auditoría.
  auditor;

  /// Sentencia fija: nunca se interpola un rol enviado por el cliente.
  String get setLocalRole => switch (this) {
    admin => 'SET LOCAL ROLE taller_admin',
    mecanico => 'SET LOCAL ROLE taller_mecanico',
    auditor => 'SET LOCAL ROLE taller_auditor',
  };
}

/// Identidad validada por PostgreSQL y conservada en el servidor.
class AuthIdentity {
  /// Crea la identidad a partir del resultado del login, nunca del cliente.
  const AuthIdentity({
    required this.userId,
    required this.workshopId,
    required this.userPublicId,
    required this.workshopPublicId,
    required this.role,
    required this.name,
  });

  /// Identificador interno; no se serializa.
  final int userId;

  /// Identificador interno; no se serializa.
  final int workshopId;

  /// Identificador público del usuario.
  final String userPublicId;

  /// Identificador público del taller.
  final String workshopPublicId;

  /// Rol validado en la base de datos.
  final UserRole role;

  /// Nombre de la persona autenticada.
  final String name;

  /// Representación pública sin ids secuenciales ni credenciales.
  Map<String, Object> toPublicJson() => {
    'usuario': {'id_publico': userPublicId, 'nombre': name, 'rol': role.name},
    'taller': {'id_publico': workshopPublicId},
  };
}

/// Sesión que ya no corresponde a un usuario, rol o taller activo.
class InvalidSession implements Exception {
  /// Error deliberadamente genérico.
  const InvalidSession();
}
