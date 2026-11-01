# Autenticación de RE-api

## Alcance

Login, sesión, cierre de sesión y configuración del taller autenticado. Se utilizan las tablas y funciones versionadas en RE-db, incluidas V011 y V012. El login actualiza intentos, bloqueo y último ingreso, y genera la auditoría prevista en la base.

## Iniciar la API

```powershell
cd C:\__apps\re-app\Backend_Repuestos_Exactos
dart pub get
dart pub global run dart_frog_cli:dart_frog dev --port 8081
```

Si había un servidor abierto, detenerlo con Ctrl+C e iniciarlo nuevamente.

## Probar desde PowerShell

El correo es el de un usuario existente. Para las semillas, la clave es CLAVE_DEMO del .env de RE-db; no es APP_BACKEND_PASSWORD, que corresponde a la conexión del servidor.

```powershell
$credencial = Get-Credential -Message "Usuario de Repuestos Exactos"
$cuerpo = @{
  email = $credencial.UserName
  password = $credencial.GetNetworkCredential().Password
} | ConvertTo-Json

$sesion = Invoke-RestMethod -Method Post `
  -Uri "http://localhost:8081/auth/login" `
  -ContentType "application/json" -Body $cuerpo
Remove-Variable cuerpo

$cabeceras = @{ Authorization = "Bearer $($sesion.access_token)" }
Invoke-RestMethod "http://localhost:8081/auth/me" -Headers $cabeceras
Invoke-RestMethod "http://localhost:8081/settings" -Headers $cabeceras
Invoke-RestMethod -Method Post `
  -Uri "http://localhost:8081/auth/logout" -Headers $cabeceras
```

Usuarios ficticios disponibles en RE-db/db/seeds/02_talleres_y_usuarios.sql. Ejemplos: admin@losaromos.example y admin@nuble.example pertenecen a talleres diferentes. Los perfiles públicos habilitados son propietario y mecanico; los auditores históricos no pueden ingresar.

## Contrato HTTP

| Ruta | Método | Autenticación | Respuesta correcta |
|---|---|---|---|
| /auth/login | POST | Pública | 200: token, vencimiento, usuario y taller públicos |
| /auth/me | GET | Bearer | 200: usuario, taller y vencimiento |
| /auth/refresh | POST | Cookie + X-RE-Session | 200: acceso nuevo y cookie rotada |
| /auth/logout | POST | Bearer o cookie; idempotente | 204 sin cuerpo y cookie eliminada |
| /settings | GET | Bearer | 200: columnas de q_configuracion |

El login admite exactamente email y password de tipo string. El correo se normaliza; la contraseña no se recorta. El cuerpo se limita a 4 KiB y la contraseña a 72 bytes UTF-8 para respetar bcrypt.

La respuesta contiene access_token, token_type (Bearer), expires_in (segundos restantes, hasta 3600), expires_at (UTC), usuario {id_publico, nombre, rol} y taller {id_publico}. No contiene ids internos ni credenciales. Las respuestas llevan Cache-Control: no-store.

Errores:

- 400: JSON o campos inválidos; no se aceptan rol ni taller en el cuerpo del login.
- 401 invalid_credentials: mismo error para contraseña incorrecta, correo inexistente, usuario/taller inactivo o cuenta bloqueada.
- 401 invalid_session: token ausente, desconocido, vencido o revocado; también si cambió el rol o se desactivó el usuario/taller.
- 403 profile_not_enabled: credenciales válidas de un perfil histórico no habilitado para la aplicación.
- 405: método incorrecto, con cabecera Allow.
- 413: cuerpo demasiado grande.
- 415: se requiere application/json.
- 503: base no disponible, tiempo de espera o capacidad de sesiones alcanzada; sin detalles SQL privados.

## Contexto del taller

La identidad de contraseña viene de fn_autenticar_aplicacion, que valida credenciales y resuelve el perfil mediante fn_perfil_usuario. Cada petición protegida toma el rol de una enumeración cerrada, ejecuta SET LOCAL ROLE y establece app.taller_id, app.usuario_id, app.ip_origen y app.request_id dentro de una transacción. Los ids y el rol enviados por el cliente no se utilizan.

Se revalidan usuario y taller activos, ids públicos, rol técnico y perfil de negocio antes de ejecutar la ruta. El nombre se obtiene del usuario actual al resolver la sesión. La IP procede del socket directo; no se confía en X-Forwarded-For. Si se incorpora un proxy, habrá que configurar explícitamente su tratamiento.

Las rutas protegidas reciben AuthSession y TxSession en RequestContext. Sus consultas deben completarse dentro del handler, sin callbacks posteriores ni streams diferidos. Errores HTTP o excepciones provocan rollback. El login es distinto: el resultado de credenciales incorrectas se confirma para conservar intentos y auditoría.

/settings no recibe un taller: RLS devuelve solo el taller del contexto. El enum tema se convierte explícitamente a texto para JSON.

## Sesiones

Tokens aleatorios de 256 bits, guardados sólo como hashes SHA-256 en PostgreSQL desde V017. Acceso de una hora y familia con vencimiento absoluto de siete días, sin extensión ilimitada. POST /auth/refresh rota acceso y renovación; POST /auth/logout revoca la familia. Las familias vencidas y sus hashes consumidos se limpian en lotes acotados al emitir sesiones nuevas.

PostgreSQL comparte las sesiones entre instancias y conserva las válidas al reiniciar la API. El almacén en memoria de SessionStore queda sólo como doble para pruebas que no proporcionan Database. Flutter web restaura mediante cookie HttpOnly y mantiene el acceso únicamente en memoria.

## Pruebas

```powershell
dart analyze
dart test
```

Integración contra PostgreSQL y una API de prueba ya levantada:

```powershell
$env:RUN_DATABASE_TESTS = "true"
$env:RE_DB_ENV_FILE = "C:\__apps\re-app\RE-db\.env"
$env:TEST_API_URL = "http://localhost:8081"
try { dart test } finally {
  Remove-Item Env:RUN_DATABASE_TESTS
  Remove-Item Env:RE_DB_ENV_FILE
  Remove-Item Env:TEST_API_URL
}
```

Sin estas variables se omiten las pruebas de integración correspondientes. Las pruebas usan las semillas y generan auditoría normal de login. Verifican los dos perfiles habilitados, el rechazo de perfiles históricos, aislamiento entre talleres, reutilización de una sola conexión, limpieza del contexto tras commit/rollback, rechazo de identidades inconsistentes, vencimiento, revocación y HTTP. No ejecutan migraciones ni modifican datos de negocio.

Detalle de propiedad, invitaciones y controles SQL: [propietario y mecánico](propietario_y_mecanico.md).

## Persistencia y renovación web (V017)

POST /auth/refresh es público respecto del Bearer vencido, pero exige la cookie re_refresh y X-RE-Session: 1. La cookie es HttpOnly, host-only, Path=/auth, SameSite=Strict y Secure salvo HTTP loopback de desarrollo. No se devuelve el refresh en JSON ni se guarda en localStorage. CORS permite credenciales sólo a los orígenes exactos configurados y admite el header de sesión; en producción frontend/API deben ser HTTPS y del mismo sitio. En local, usar localhost para ambos o 127.0.0.1 para ambos, sin mezclarlos.

El servidor revalida usuario, taller y perfil al resolver y renovar. Rota ambos tokens; un token consumido no obtiene acceso. Durante diez segundos, un uso simultáneo devuelve 409 refresh_in_progress sin modificar la cookie para no expulsar otra pestaña legítima. Fuera de esa tolerancia, la repetición revoca la familia. Cada nuevo token conserva el límite absoluto original. Interrumpir una rotación antes de recibir su cookie puede requerir nuevo ingreso; no se recuperan credenciales usadas a cambio de tolerar repetición.

POST /auth/logout es idempotente: acepta Bearer o cookie, incluso con acceso vencido, revoca la familia y borra la cookie. Cuando recibe cookie exige el header de sesión. Un logout sin credenciales sólo borra la cookie. El frontend espera la renovación en vuelo antes de completar logout y conserva en localStorage únicamente una bandera de intención de salida: si no hubo red, no intenta reingresar automáticamente al recargar. La revocación del servidor sólo queda confirmada si éste respondió.

Al cargar, Flutter muestra una espera de restauración antes de ofrecer el login. Una falla de red permite reintentar sin borrar la cookie. Durante uso, renueva dos minutos antes de vencer y comparte una sola renovación ante respuestas 401 concurrentes; repite como máximo una vez la petición protegida. Respuestas tardías de una sesión anterior no pueden ejecutar la operación bajo una cuenta nueva. Tras la instalación de V017 hace falta un login inicial: las antiguas sesiones en memoria no tenían cookie de renovación.

La persistencia automática del cliente en este incremento es web. Los clientes Bearer existentes conservan su contrato; las plataformas nativas no incorporan todavía almacenamiento seguro persistente de refresh. Cerrar nuestra sesión no cierra Google; cuando la familia vence o es revocada, Google puede volver a mostrar su selector de cuentas.

Validación: sesiones persistentes entre instancias/reinicio, rotación, concurrencia, logout, protección CSRF/CORS, baja de usuario y vencimiento absoluto. La suite SQL incorpora db/tests/13_sesiones_persistentes.sql; las pruebas HTTP usan una copia desechable con DB_NAME prefijada re_api_preflight_.

Fuentes técnicas: [cookies](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie), [rotación y repetición](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14).

El almacén conserva el límite de 10.000 familias activas, compartido entre instancias de la API. Al alcanzarlo, rechaza una nueva sesión sin expulsar las existentes.
