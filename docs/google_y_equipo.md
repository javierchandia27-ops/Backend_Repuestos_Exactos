# Google, registro de talleres e invitaciones

Implementación para el frontend Flutter web, Dart Frog y PostgreSQL. Se conserva el ingreso con correo y contraseña. Google está deshabilitado hasta configurar un Client ID real; no se creó una credencial de prueba ni un mecanismo para omitir su validación.

## Activación local

1. En Google Cloud, crear o seleccionar un proyecto. En Google Auth Platform configurar Branding, Audience externa y el cliente OAuth de tipo **Aplicación web**.
2. Registrar los orígenes JavaScript autorizados: `http://localhost` y `http://localhost:8080`. En producción usar el origen HTTPS real. No se necesita habilitar Gmail, Drive ni People API.
3. Copiar el Client ID público en `Backend_Repuestos_Exactos/.env`:

```dotenv
GOOGLE_CLIENT_IDS=TU_CLIENT_ID.apps.googleusercontent.com
FRONTEND_URL=http://localhost:8080
```

El primer ID de la lista es el cliente web que dibuja el botón. La API verifica que la audiencia pertenezca a esta lista. No colocar un Client Secret ni una API key en Flutter. Este flujo usa el botón oficial de Google y un ID token; no requiere Firebase.

4. Reiniciar los servicios desde la raíz:

```powershell
.\Iniciar-RepuestosExactos.ps1 -Detener
.\Iniciar-RepuestosExactos.ps1 -SinNavegador
```

5. Abrir `http://localhost:8080`. `GET http://localhost:8081/auth/google/config` debe devolver `enabled: true` y el Client ID público.

Para una base existente aplicar **una sola vez** `RE-db/db/migrations/V011__google_y_onboarding.sql`. Desde RE-db, con Git Bash y Docker configurados: `bash db/scripts/migrate.sh V011`. No ejecutar todas las migraciones sobre un volumen existente ni usar reset. La migración ya fue aplicada en este equipo y se dejó respaldo previo en `RE-db/backups/pre-google-20261031.dump`, excluido de Git.

Para habilitar los dos perfiles de negocio se aplica después V012; ver [propietario y mecánico](propietario_y_mecanico.md). V011 ya aplicada no se repite.

## Recorridos

- **Cuenta ya vinculada:** continuar con Google, validar token, resolver usuario y emitir una sesión de la aplicación con su rol y taller actuales.
- **Cuenta existente con contraseña:** continuar con Google y confirmar la contraseña de esa cuenta. Se vincula el identificador estable de Google a ese usuario; no se crea otro taller ni se cambia el rol.
- **Dueño nuevo:** continuar con Google, escribir el nombre y pulsar Crear mi taller. Taller, configuración, primer usuario propietario, propiedad explícita del taller y vinculación se crean en una transacción.
- **Empleado nuevo:** el propietario abre Ajustes → Equipo del taller, introduce el correo y genera una invitación. Comparte el enlace por su medio habitual. El destinatario abre el enlace, continúa con Google con el mismo correo y acepta.
- **Regeneración/revocación:** el nuevo enlace invalida el anterior. Cada enlace vence en siete días y se consume una sola vez. La lista muestra pendientes, aceptadas, vencidas y revocadas.

El envío automático de correos no está incluido: la pantalla permite copiar el enlace. No se envían mensajes a terceros desde esta implementación. Para automatizarlo se necesita configurar un proveedor de correo transaccional y agregar su entrega a partir del flujo existente.

## Responsabilidades y permisos

Google acredita identidad; nuestra base determina permisos. `identidad_externa` vincula `(proveedor, sujeto)` con `usuario`. No se enlazan cuentas existentes sólo por coincidir el email.

`invitacion_taller` conserva correo, taller, rol, autor, vencimiento y hash del token. El enlace completo sólo se devuelve al generarlo. Las políticas RLS y la API limitan su gestión al propietario de ese taller. No se aceptan roles ni identificadores de taller en los cuerpos de registro Google.

`taller_admin` hereda las operaciones de `taller_mecanico` para permitir al dueño diagnosticar y cotizar. Conserva su identidad de administrador en auditoría y el aislamiento de su taller. El perfil público `mecanico` no puede gestionar invitaciones. `admin` y `auditor` se conservan como roles técnicos históricos; sólo la relación explícita de propiedad habilita el perfil `propietario`.

La función restringida `fn_google_acceso` pertenece a `app_funciones` y sólo el rol de conexión del backend puede ejecutarla. Las tablas de identidades no son accesibles a los roles de taller. El backend sigue conectándose como `app_backend_user`, nunca como superusuario.

## API

| Método | Ruta                     | Acceso / resultado                                               |
| ------ | ------------------------ | ---------------------------------------------------------------- |
| GET    | /auth/google/config      | Público. Habilitación y Client ID web.                           |
| POST   | /auth/google/challenge   | Público. Nonce aleatorio de diez minutos.                        |
| POST   | /auth/google             | Público. `id_token` y `nonce`; sesión o ticket de incorporación. |
| POST   | /auth/google/complete    | Público. Ticket temporal y acción `register`, `accept` o `link`. |
| GET    | /invitations             | Propietario. Últimas cien invitaciones de su taller.           |
| POST   | /invitations             | Propietario. `email`; genera enlace como mecánico.                  |
| POST   | /invitations/{id}/revoke | Propietario. Revoca invitación pendiente.                      |

El ticket de incorporación **no** permite consultar datos del taller. Para `register` se envía `workshop_name`; para `accept`, `invitation_token`; para `link`, `password`. Los endpoints limitan tamaño de JSON, claves permitidas e intentos por IP. Se conserva CORS con orígenes explícitos y respuestas de autenticación sin caché.

## Validación de Google

Firma RS256 con las claves públicas de Google, caché según Cache-Control, emisor, audiencia, expiración, fecha de emisión, correo verificado y nonce de un solo uso. La credencial Google se utiliza para emitir nuestra sesión; no reemplaza el Bearer de la API.

Para altas e invitaciones se requiere Gmail o Google Workspace, donde Google es autoritativo sobre el correo. Una cuenta Google que usa un correo externo puede vincularse a una cuenta existente confirmando su contraseña. Dar de alta correos externos sin contraseña requiere añadir verificación propia de correo.

Las sesiones y los desafíos permanecen en memoria, como las sesiones actuales: reiniciar la API obliga a ingresar nuevamente. Para varias instancias se necesita un almacén compartido. La integración Google de esta entrega es web; en las aplicaciones nativas se conserva el ingreso por contraseña y se indica continuar con Google desde la web.

El modelo actual permite un taller y un perfil por usuario, con email único. Una invitación no transfiere una cuenta de otro taller. Si se requiere trabajar en varias empresas, habrá que agregar membresías y selección de taller.

## Comprobaciones

- Backend: `dart analyze` y `dart test`. Con `RUN_DATABASE_TESTS=true`, `RE_DB_ENV_FILE` apuntando a RE-db/.env y `TEST_API_URL=http://localhost:8081` se activan las pruebas existentes contra PostgreSQL y HTTP.
- `test/auth/google_token_verifier_test.dart` usa claves RSA generadas en la prueba; verifica firma, claims, caché y rechazo de tokens inválidos. No son credenciales de Google reales.
- `test/auth/onboarding_store_test.dart` comprueba vencimiento, consumo único, concurrencia y límites.
- `test/auth/invitation_database_integration_test.dart` prueba generación, reemplazo y revocación contra PostgreSQL con rollback.
- `RE-db/db/tests/11_google_onboarding.sql` prueba altas, roles, aislamiento, coincidencia de correo, expiración y revocación con rollback. Sus claims sintéticos no certifican el login real con Google.
- Frontend: `flutter test`, incluidas las pruebas de control de sesión Google y registro en pantalla estrecha.
- Se debe completar la prueba real de selección de cuenta Google, origen autorizado y credencial emitida por Google cuando esté disponible el Client ID.

## Referencias

- [Configuración del cliente web de Google](https://developers.google.com/identity/gsi/web/guides/get-google-api-clientid)
- [Validación de ID tokens y vinculación de cuentas](https://developers.google.com/identity/gsi/web/guides/verify-google-id-token)
- [API JavaScript del botón oficial](https://developers.google.com/identity/gsi/web/reference/js-reference)
- [Bindings oficiales de Flutter para Google Identity Services](https://pub.dev/packages/google_identity_services_web)
