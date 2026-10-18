# Autenticación de RE-api

## Alcance

Login, sesión, cierre de sesión y configuración del taller autenticado. Se reutilizan las tablas y la función de RE-db. No se crean ni alteran tablas. El login actualiza intentos, bloqueo y último ingreso, y genera la auditoría prevista en la base.

## Iniciar la API

```powershell
cd C:\Users\felip\source\repos\RE-api
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

Usuarios ficticios disponibles en RE-db/db/seeds/02_talleres_y_usuarios.sql. Ejemplos: admin@losaromos.example y admin@nuble.example pertenecen a talleres diferentes. También hay roles mecanico y auditor.

## Contrato HTTP

| Ruta | Método | Autenticación | Respuesta correcta |
|---|---|---|---|
| /auth/login | POST | Pública | 200: token, vencimiento, usuario y taller públicos |
| /auth/me | GET | Bearer | 200: usuario, taller y vencimiento |
| /auth/logout | POST | Bearer | 204 sin cuerpo |
| /settings | GET | Bearer | 200: columnas de q_configuracion |

El login admite exactamente email y password de tipo string. El correo se normaliza; la contraseña no se recorta. El cuerpo se limita a 4 KiB y la contraseña a 72 bytes UTF-8 para respetar bcrypt.

La respuesta contiene access_token, token_type (Bearer), expires_in (3600), expires_at (UTC), usuario {id_publico, nombre, rol} y taller {id_publico}. No contiene ids internos ni credenciales. Las respuestas llevan Cache-Control: no-store.

Errores:

- 400: JSON o campos inválidos; no se aceptan rol ni taller en el cuerpo del login.
- 401 invalid_credentials: mismo error para contraseña incorrecta, correo inexistente, usuario/taller inactivo o cuenta bloqueada.
- 401 invalid_session: token ausente, desconocido, vencido o revocado; también si cambió el rol o se desactivó el usuario/taller.
- 405: método incorrecto, con cabecera Allow.
- 413: cuerpo demasiado grande.
- 415: se requiere application/json.
- 503: base no disponible, tiempo de espera o capacidad de sesiones alcanzada; sin detalles SQL privados.

## Contexto del taller

La identidad viene de fn_autenticar_usuario. Cada petición protegida toma el rol de una enumeración cerrada, ejecuta SET LOCAL ROLE y establece app.taller_id, app.usuario_id, app.ip_origen y app.request_id dentro de una transacción. Los ids y el rol enviados por el cliente no se utilizan.

Se revalidan usuario y taller activos, ids públicos y rol antes de ejecutar la ruta. El nombre de la sesión corresponde al login. La IP procede del socket directo; no se confía en X-Forwarded-For. Si se incorpora un proxy, habrá que configurar explícitamente su tratamiento.

Las rutas protegidas reciben AuthSession y TxSession en RequestContext. Sus consultas deben completarse dentro del handler, sin callbacks posteriores ni streams diferidos. Errores HTTP o excepciones provocan rollback. El login es distinto: el resultado de credenciales incorrectas se confirma para conservar intentos y auditoría.

/settings no recibe un taller: RLS devuelve solo el taller del contexto. El enum tema se convierte explícitamente a texto para JSON.

## Sesiones

Tokens aleatorios de 256 bits, guardados como hashes SHA-256. Duración absoluta de una hora, sin renovación automática. Máximo de 10.000 sesiones activas; las vencidas se purgan al emitir nuevas. Logout revoca inmediatamente.

La memoria pertenece a una instancia y se pierde al reiniciar. Para varias instancias o persistencia se debe reemplazar el almacén por uno compartido. Flutter todavía no está conectado a estas rutas.

## Pruebas

```powershell
dart analyze
dart test
```

Integración contra PostgreSQL y una API de prueba ya levantada:

```powershell
$env:RUN_DATABASE_TESTS = "true"
$env:RE_DB_ENV_FILE = "C:\Users\felip\source\repos\RE-db\.env"
$env:TEST_API_URL = "http://localhost:8081"
try { dart test } finally {
  Remove-Item Env:RUN_DATABASE_TESTS
  Remove-Item Env:RE_DB_ENV_FILE
  Remove-Item Env:TEST_API_URL
}
```

Sin estas variables se omiten las pruebas de integración correspondientes. Las pruebas usan las semillas y generan auditoría normal de login. Verifican tres roles, aislamiento entre talleres, reutilización de una sola conexión, limpieza del contexto tras commit/rollback, rechazo de identidades inconsistentes, vencimiento, revocación y HTTP. No ejecutan migraciones ni modifican datos de negocio.
