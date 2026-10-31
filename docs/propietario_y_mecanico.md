# Propietario y mecánico

## Regla del negocio

PostgreSQL determina el perfil. La aplicación ofrece únicamente **propietario** y **mecánico**. El propietario también realiza el trabajo operativo del mecánico; no necesita otra cuenta.

| Capacidad | Propietario | Mecánico |
|---|---|---|
| Trabajar con vehículos, diagnósticos y cotizaciones visibles de su taller | Sí | Sí |
| Consultar historial y catálogo, buscar por VIN respetando privacidad | Sí | Sí |
| Generar, consultar y revocar invitaciones para mecánicos | Sí | No |
| Administrar usuarios, configuración, dispositivos y solicitudes de privacidad | Sí | No |
| Nombrar administradores, auditores o más propietarios desde invitaciones | No | No |
| Cambiar la propiedad o desactivar al propietario | No | No |

La primera fila describe los permisos de base de datos. Los endpoints operativos disponibles siguen siendo los existentes: esta entrega no agrega creación de diagnósticos ni gestión completa de cotizaciones. Configuración y administración de usuarios conservan su alcance HTTP actual; los nuevos controles de escritura también se aplican en SQL para futuras rutas.

## Fuente de verdad y compatibilidad

- `taller.propietario_usuario_id` referencia `usuario(id,taller_id)` mediante una clave foránea compuesta: el propietario debe pertenecer a ese taller.
- `propietario_asignado_en` registra la asignación. Un trigger valida que el usuario sea activo y tenga el rol técnico correspondiente, y evita transferencias mediante actualizaciones generales.
- `v_usuario_perfil` deriva `propietario` cuando coincide esa relación explícita; deriva `mecanico` para el rol operativo activo. Usuario y taller deben estar activos. Devuelve NULL para perfiles históricos no habilitados.
- `fn_perfil_usuario` y `fn_es_propietario` centralizan la resolución y el control de propiedad. RLS mantiene el aislamiento entre talleres.
- El enum técnico `admin/mecanico/auditor` y los grupos PostgreSQL se conservan para mantener referencias, auditoría y pruebas históricas. No son opciones del registro ni de la pantalla de equipo. Tener `admin` sin ser el propietario no habilita la aplicación ni permite gestionar el taller.
- La API publica `usuario.rol` con `propietario` o `mecanico`. Internamente, propietario utiliza `taller_admin`, que ya hereda las operaciones de `taller_mecanico`.

El login con contraseña usa `fn_autenticar_aplicacion`; Google devuelve el mismo perfil desde `fn_google_acceso`. Cada petición protegida vuelve a comprobar usuario, taller, rol técnico y perfil contra PostgreSQL. Manipular Flutter o enviar un rol en JSON no cambia los permisos.

## Incorporación

1. El dueño continúa con Google y elige **Crear mi taller**. Se crean taller, configuración, usuario, vínculo Google y propiedad en una sola transacción. No se solicita elegir rol.
2. El propietario entra en **Ajustes → Equipo del taller**, escribe el correo y genera una invitación. El servidor fija `mecanico`. El enlace se comparte manualmente; no se envía correo automáticamente.
3. El mecánico abre el enlace y acepta con el mismo correo verificado por Google. La invitación debe estar vigente, sin revocar, sin consumir y haber sido emitida por el propietario actual. La aceptación no permite cambiar de taller una cuenta ya existente.
4. El mecánico obtiene su sesión y opera únicamente en ese taller. No tiene gestión de equipo. El propietario conserva los mismos accesos operativos más sus facultades de gestión.

Las invitaciones antiguas pendientes que ofrecían otro rol se revocan conservando el registro. El endpoint acepta por compatibilidad `role: mecanico`, aunque el frontend envía sólo `email`; cualquier otro rol se rechaza. No hay altas de administrador delegado ni auditor en este alcance.

## Migración V012

Archivo: [V012__propietario_y_mecanico.sql](../../RE-db/db/migrations/V012__propietario_y_mecanico.sql). Requiere V011 y se aplica una vez, dentro de una transacción. Desde RE-db con Git Bash y Docker:

~~~bash
bash db/scripts/migrate.sh V012
~~~

No repetir migraciones ya aplicadas. No ejecutar reset sobre el volumen en uso. En este equipo V012 ya está aplicada y se generó un respaldo previo en `RE-db/backups/`.

La migración asigna explícitamente sólo los dos propietarios ficticios conocidos de las semillas. No toma al primer administrador como dueño de cualquier taller. Los talleres heredados sin propietario requieren una asignación verificada por operación de plataforma; mientras tanto no se permite ingresar como propietario ni aceptar invitaciones emitidas por un administrador sin propiedad. La asignación de la cuenta real confirmada en este entorno se hizo por sus identificadores públicos, fuera de la migración versionada.

Las cuentas históricas de auditor se conservan y el login de la aplicación responde `403 profile_not_enabled`. No se convierten automáticamente en mecánicos. Su tratamiento debe decidirlo el propietario con una política explícita antes de habilitarlas.

## Traza

~~~mermaid
flowchart LR
  F[Flutter: Google o contraseña] --> A[API: autenticación]
  A --> D[PostgreSQL: perfil por propiedad y rol]
  D --> S[Sesión: propietario o mecánico]
  S --> R[Petición protegida: revalidar perfil y taller]
  R --> T[Transacción con SET LOCAL ROLE y contexto]
  T --> P[RLS y triggers de propiedad]
  P --> O[Datos del propio taller]
~~~

## Verificación y límites

- `RE-db/db/tests/12_propietario_y_mecanico.sql` prueba registro y propiedad atómicos, incorporación por invitación, aislamiento, rechazo de promociones, gestión exclusiva y protección del propietario con rollback.
- `test/auth/business_profiles_http_integration_test.dart` prueba perfiles devueltos, permisos del equipo y rechazo de roles manipulados sobre HTTP real.
- `Repuestos-Exactos/test/team_profiles_test.dart` prueba la pantalla estrecha: propietario invita como mecánico; mecánico no carga ni muestra las operaciones de equipo.
- El registro Google en SQL usa claims sintéticos para probar reglas de negocio. Esto no sustituye una nueva autenticación interactiva con un token real de Google.
- En el entorno local se validó la versión nueva en 8082 (API) y 8083 (Flutter). Los procesos anteriores de 8080/8081 requieren cierre por el usuario porque Windows denegó su terminación desde esta sesión. Google sólo funcionará en los orígenes configurados en su cliente OAuth; no se cambió esa configuración para las pruebas alternativas.
- Transferencia de propiedad, múltiples talleres por usuario y un administrador delegado requieren flujos propios. No se habilitaron implícitamente.

Evidencia de esta ejecución: [validación de propietario y mecánico](evidencia/propietario_mecanico_validacion.json). Resultado: 517 comprobaciones SQL, 53 pruebas backend y 42 pruebas Flutter; dos pruebas Flutter opcionales omitidas. Los análisis de ambos proyectos Dart terminaron sin diagnósticos.
