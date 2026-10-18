# RE-api — Backend de Repuestos Exactos

API REST en Dart con Dart Frog, conectada al PostgreSQL local de `RE-db` mediante el controlador `postgres`. Implementa conectividad, autenticación, contexto transaccional por taller e historial real de diagnósticos, catálogo de repuestos y búsqueda local por VIN.

## Configuración local

Requisitos: Dart SDK compatible con `pubspec.yaml`, Dart Frog CLI y el contenedor PostgreSQL de `RE-db` levantado y migrado.

```powershell
cd ./Backend_Repuestos_Exactos 
dart pub get
```

La instalación inicial de la herramienta es `dart pub global activate dart_frog_cli`. Si PowerShell no reconoce Dart, agregar `C:\flutter\bin` al PATH; para la sesión actual: `$env:Path = "C:\flutter\bin;$env:Path"`.

Si aún no existe `.env`, copiar `.env.example` a `.env`. Completar `DB_NAME` con `POSTGRES_DB` de `RE-db` y `DB_PASSWORD` con su `APP_BACKEND_PASSWORD`. El usuario es `app_backend_user`, no el superusuario del contenedor. El archivo local queda ignorado por Git. No sobrescribir uno ya configurado.

Variables: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` y `DB_SSL_MODE`. Las variables del proceso tienen prioridad sobre `.env`. Se valida la presencia de valores y el rango del puerto al iniciar. TLS usa `verify-full` por defecto; el ejemplo configura `disable` para el contenedor local sin TLS.

## Arranque

```powershell
dart pub global run dart_frog_cli:dart_frog dev --port 8081
```

Después de cambiar `.env`, dependencias o el arranque personalizado, detener con `Ctrl+C` e iniciar nuevamente.

## Rutas disponibles

- `GET /`: confirma que la API responde, independientemente del estado de PostgreSQL.
- `GET /health/database`: ejecuta una consulta real y comprueba que la sesión usa `app_backend_user` y que existen `vehiculo`, `sesion_diagnostico` y `cotizacion` en `public`. No lee registros ni lista tablas por HTTP. No valida todas las migraciones, permisos ni columnas.

Conexión correcta: HTTP 200 en `http://localhost:8081/health/database`:

```json
{"status":"ok","database":"connected"}
```

Si falla la conexión, faltan las tablas comprobadas o el rol no coincide: HTTP 503 con `{"status":"error","database":"unavailable"}`. No se devuelven excepciones SQL ni valores de configuración. Otros métodos responden 405.

## Consultar las tablas desde la terminal

```powershell
dart run tool/check_database.dart
```

Verifica la conexión y lista los nombres de las tablas de `public` mediante el catálogo de PostgreSQL. No modifica el esquema ni consulta datos personales. Devuelve código 1 si no puede comprobar la conexión y las tablas requeridas.

## Estructura

```text
main.dart                         Arranque e inyección de la conexión compartida
lib/config/database_config.dart   Configuración y validación del entorno
lib/database/database.dart        Pool PostgreSQL y consultas de diagnóstico
routes/index.dart                 Estado del proceso API
routes/health/database.dart       Estado de PostgreSQL
tool/check_database.dart          Diagnóstico local y listado de tablas
test/                             Pruebas unitarias y de integración
```

El pool abre conexiones bajo demanda, tiene un máximo de 5 conexiones y tiempos de espera de 5 segundos para conexión y consultas. El script local y las pruebas cierran sus conexiones al terminar.

## Validación

```powershell
dart analyze
dart test
```

La prueba contra PostgreSQL se omite normalmente. Para ejecutarla junto con las demás, usando la base local:

```powershell
$env:RUN_DATABASE_TESTS = "true"
try { dart test } finally { Remove-Item Env:RUN_DATABASE_TESTS }
```

La prueba real verifica metadatos, el rechazo de lectura operativa sin asumir rol, una lectura del catálogo global de marcas y la limpieza de `SET LOCAL ROLE` después de COMMIT y ROLLBACK. No modifica datos de negocio.

## Autenticación

| Ruta | Método | Acceso |
|---|---|---|
| /auth/login | POST | Público, JSON email y password |
| /auth/me | GET | Token Bearer |
| /auth/logout | POST | Token Bearer |
| /settings | GET | Token Bearer; solo su taller |

El token es opaco, dura una hora y su identidad se guarda en el servidor. Se revalidan usuario, taller activo y rol en cada petición protegida. Reiniciar la API cierra todas las sesiones. Las rutas nuevas quedan protegidas por defecto; solo son públicas /, /health/database y /auth/login.

Guía y ejemplos: [docs/autenticacion.md](docs/autenticacion.md).

## Módulos de negocio

- `GET /sessions`: historial del taller autenticado, con filtros por estado y paginación por cursor.
- Flutter consume autenticación, configuración, historial y búsqueda de catálogo con compatibilidad.
- `GET /catalog/brands`, `/catalog/brands/{marca}/models`, `/catalog/dtc` y `/catalog/dtc/{codigo}/parts`.
- `GET /search?vin=...`: vehículo registrado y visible del taller, para administración y mecánica.
- Contrato y alcance de búsqueda: [docs/busqueda.md](docs/busqueda.md).
- La creación real de diagnósticos sigue pendiente.
- Estructura y límites: [docs/arquitectura.md](docs/arquitectura.md).
- Contrato y pruebas del historial: [docs/historial.md](docs/historial.md).

Las migraciones y el contrato SQL siguen perteneciendo a RE-db.

## Acceso desde Flutter web

La API permite por defecto los orígenes http://localhost:8080 y http://127.0.0.1:8080. CORS_ALLOWED_ORIGINS puede definir una lista de orígenes exactos separados por comas; no se admiten comodines. Reiniciar la API después de cambiarla. Los preflight OPTIONS se resuelven antes de la autenticación; el login y las rutas protegidas mantienen sus requisitos habituales.
