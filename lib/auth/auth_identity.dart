/// Perfiles de negocio resueltos por PostgreSQL.
enum UserRole {
  /// Propietario explícito del taller, validado en PostgreSQL.
  propietario,

  /// Trabajo diario de diagnóstico y cotización.
  mecanico;

  /// Grupo técnico de PostgreSQL; no se recibe del cliente.
  String get databaseRole => switch (this) {
    propietario => 'admin',
    mecanico => 'mecanico',
  };

  /// Sentencia fija para el grupo SQL que corresponde al perfil.
  String get setLocalRole => switch (this) {
    propietario => 'SET LOCAL ROLE taller_admin',
    mecanico => 'SET LOCAL ROLE taller_mecanico',
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
