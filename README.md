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

El token es opaco, dura una hora y su identidad se guarda en el servidor. Se revalidan usuario, taller activo, rol técnico y perfil de negocio en cada petición protegida. Reiniciar la API cierra todas las sesiones. Las rutas nuevas quedan protegidas por defecto; son públicas /, /health/database, /auth/login y los endpoints explícitos /auth/google, /auth/google/config, /auth/google/challenge y /auth/google/complete. Estos últimos validan la credencial o el ticket temporal antes de conceder acceso.

Guía y ejemplos: [docs/autenticacion.md](docs/autenticacion.md).

## Módulos de negocio

- `GET /sessions`: historial del taller autenticado, con filtros por estado y paginación por cursor.
- Flutter consume autenticación, configuración, historial y búsqueda de catálogo con compatibilidad.
- `GET /catalog/brands`, `/catalog/brands/{marca}/models`, `/catalog/dtc` y `/catalog/dtc/{codigo}/parts`.
- `GET /search?vin=...`: vehículo registrado y visible del taller, para propietario y mecánico.
- Contrato y alcance de búsqueda: [docs/busqueda.md](docs/busqueda.md).
- La captura OBD se registra con POST /sessions; ver el contrato del incremento V015 al final.
- Estructura y límites: [docs/arquitectura.md](docs/arquitectura.md).
- Contrato y pruebas del historial: [docs/historial.md](docs/historial.md).

Las migraciones y el contrato SQL siguen perteneciendo a RE-db.

## Acceso desde Flutter web

La API permite por defecto los orígenes http://localhost:8080 y http://127.0.0.1:8080. CORS_ALLOWED_ORIGINS puede definir una lista de orígenes exactos separados por comas; no se admiten comodines. Reiniciar la API después de cambiarla. Los preflight OPTIONS se resuelven antes de la autenticación; el login y las rutas protegidas mantienen sus requisitos habituales.

## Google y equipo del taller

Configuración y recorridos de Google, registro de talleres e invitaciones: [guía](docs/google_y_equipo.md).

Perfiles de negocio y migración V012: [propietario y mecánico](docs/propietario_y_mecanico.md). La propiedad se guarda explícitamente en PostgreSQL; las invitaciones incorporan sólo mecánicos.

## Mercado Libre y alternativas guardadas

Búsqueda externa, referencias técnicas y guardado por taller implementados en `feat/integracion_api`. Consulta [arquitectura, configuración y límites de acceso](docs/integracion_mercadolibre.md) y la [evidencia de validación](docs/evidencia/integracion_mercadolibre_validacion.json).

## Captura OBD2, vehículos e historial (V015)

El Bluetooth se atiende en el cliente Windows/Chrome; la API recibe observaciones normalizadas, valida el contrato y persiste bajo el contexto autenticado del taller. No abre puertos del PC ni acepta taller, autor, descripción o precios asignados por el cliente.

| Método y ruta | Contrato y acceso |
|---|---|
| GET /vehicles | Hasta 200 vehículos visibles; propietario/mecánico. |
| POST /vehicles | model_id, year, plate, engine. Alta mínima sin titular; no reemplaza un vehículo existente. Misma patente con otros datos: 409. |
| GET /diagnostic-devices | Inventario activo del taller. |
| POST /diagnostic-devices | Sólo propietario; name e idempotency_key UUID. Registro lógico de vLinker MC sin MAC ficticia. |
| POST /sessions | vehicle_id, device_id, kilometraje, idempotency_key UUID, captured_at UTC, protocol, services y observations. |
| GET /sessions/{id} | Detalle con vehículo, protocolo, estados de servicios y códigos/ECU/categorías; registros previos siguen siendo consultables. |

services contiene exactamente 03, 07 y 0A. Los estados son ok, empty, no_data, unsupported o partial. El modo 03 debe completarse (ok/empty); no_data no equivale a cero fallas. partial se reserva a lecturas opcionales con ECU que no soportan el servicio. observations contiene objetos code, ecu y kind (stored/pending/permanent), sin duplicados, hasta 256. JSON máximo 32 KiB; fecha entre siete días pasados y cinco minutos futuros; kilometraje entero no negativo. El cliente debe conservar la clave y el contenido del guardado para reintentar; otra carga o autor con la misma clave produce 409.

Una sola transacción inserta sesion_diagnostico, observacion_obd y los vínculos catalogados de falla_sesion. Los códigos desconocidos se conservan sin descripción inventada. No se crea cotización ni se cambia a cotizado/reparado. Historial mantiene filtros, cursores y contrato; para capturas nuevas cuenta códigos distintos, sin multiplicarlos por ECU o categoría. Las alternativas externas se vinculan usando el session_id existente y mantienen RLS y restricciones del proveedor.

Arquitectura: rutas delgadas → DTO/servicio de captura → DiagnosticCaptureRepository → transacción autenticada/RLS. V015 pertenece a RE-db. Aplicarla después de V014 con respaldo; no reinicializar la base.

Las pruebas SQL y de persistencia se ejecutaron sobre una copia aislada. La prueba Flutter optativa del recorrido completo usa serial y marketplace controlados, HTTP/BD reales, e incluye reintento concurrente, códigos desconocidos, aislamiento de talleres y asociación de alternativa. Requiere API QA generada con estas rutas, datos demo y variables RUN_OBD_HTTP_TESTS, TEST_API_URL, DB_NAME (prefijo re_api_preflight_) y DEMO_PASSWORD. Nunca apuntarla a datos de usuarios. Los dobles QA y tokens de prueba no pertenecen al código de producción.

[Traza navegable en JSON](docs/evidencia/traza_bluetooth_obd2.json) · [Resultados y aceptación pendiente de hardware](docs/evidencia/bluetooth_validacion.json).

### Actualización VIN automático

GET /vehicles acepta ahora el filtro opcional vin (17 caracteres, sin I/O/Q, normalizado), siempre bajo RLS. POST /vehicles y POST /sessions aceptan vin opcional; los clientes previos sin este campo conservan el contrato. La huella de reintento incluye VIN cuando está presente.

Al crear la captura, se bloquea el vehículo visible con FOR UPDATE y se contrasta el VIN. Si estaba vacío se completa; si es diferente se devuelve 409 vin_vehicle_mismatch. Un VIN ya asociado a otro vehículo del taller devuelve 409 vehicle_vin_conflict. La asociación y las inserciones de sesión/observaciones son atómicas: si falla el dispositivo o cualquier escritura, el VIN tampoco cambia. No se sobrescriben VIN ni se consulta identidad de otros talleres. GET /sessions/{id} muestra el VIN registrado del vehículo mediante la relación existente; no duplica identificadores en observaciones, auditoría ni tablas nuevas, y conserva la anonimización existente.

No se incorpora un decodificador externo de marca/modelo/año. Coincidir por VIN significa encontrar el registro existente en ese taller; un VIN nuevo requiere que el técnico confirme los datos. V016 de RE-db añade sólo la marca Peugeot y el modelo 3008 al catálogo. La prueba HTTP usa un Peugeot 3008 año 2017 de QA y un VIN sintético exclusivamente en una base desechable.

Pruebas específicas: test/obd_vin_test.dart (Flutter), test/diagnostic_flow_test.dart, test/obd_backend_flow_test.dart optativo y test/features/diagnostics/scan_request_test.dart (API). Fuente del formato: [ELM327](https://www.elmelectronics.com/wp-content/uploads/2016/07/ELM327DSH.pdf#page=42).
