# Historial de diagnósticos

## Contrato

GET /sessions requiere Authorization: Bearer y admite exclusivamente:

| Parámetro | Valores |
|---|---|
| limit | Entero de 1 a 100; por defecto 20 |
| status | pendiente, cotizado, completado o cancelado; omitir para todos |
| cursor | Cadena opaca entregada como next_cursor en la página anterior |

Ejemplo: GET /sessions?status=cotizado&limit=20

Respuesta: un objeto con data (lista de resúmenes) y next_cursor (cadena o null si terminó el recorrido).
Cada resumen incluye id_publico, estado, iniciada_en (UTC), metodo_ingreso, kilometraje, version, usuario_nombre, los campos vehiculo_id_publico/vehiculo_patente/vehiculo_anio/modelo_nombre/marca_nombre, fallas, severidad_maxima y cotizacion_total/cotizacion_moneda.
El importe se serializa como cadena decimal exacta, o null cuando no existe una cotización vigente. El frontend del historial muestra vehículo, fecha local, estado, usuario, método y cantidad de fallas.

El cursor contiene una fecha con microsegundos y un UUID público; es codificación, no cifrado. El repositorio comprueba que el ancla existe dentro de las políticas del taller. No incluye identificadores numéricos. Si se cambia el filtro, comenzar una nueva consulta sin cursor.

## Comportamiento

- Orden: iniciada_en DESC, id interno DESC para desempatar; solo el UUID público viaja al cliente.
- Se consultan limit + 1 filas para decidir si existe otra página.
- SQL basado en las cuatro variantes de RE-db/db/queries/q04_sesiones.sql. Los fragmentos de filtros son constantes y todos los valores van enlazados como parámetros.
- LEFT JOIN preserva las sesiones cuyo vehículo no es visible por RLS. La UI muestra “Vehículo no disponible”.
- Un taller sin sesiones o un estado sin resultados devuelve HTTP 200 con data vacía y next_cursor null.
- Filtros, límites o cursores inválidos: 400. Un cursor inexistente o de otro taller produce el mismo error invalid_cursor.
- Sesión ausente/inválida: 401. Otros métodos: 405. Fallos de base: respuesta pública controlada sin SQL ni secretos.
- El historial solo lee datos. No crea diagnósticos, modifica estados ni conecta dispositivos OBD.

## Comprobación local

Con el backend de prueba levantado, ejecutar desde RE-api:

~~~powershell
$env:RUN_DATABASE_TESTS = 'true'
$env:RE_DB_ENV_FILE = 'C:\Users\felip\source\repos\RE-db\.env'
$env:TEST_API_URL = 'http://localhost:8082'
dart test
~~~

Las pruebas usan las cuentas demo existentes y CLAVE_DEMO desde el archivo local; generan los registros habituales de login/auditoría, sin insertar datos de negocio ni modificar el esquema. Cubren los tres roles, dos talleres, las cuatro variantes de consulta, paginación sin duplicados, vehículos ocultos y rechazo de parámetros manipulados. Requieren el seed del entorno local.

Para una segunda instancia local, elegir otro puerto HTTP y de depuración:

~~~powershell
dart pub global run dart_frog_cli:dart_frog dev --port 8082 --dart-vm-service-port 8182
~~~
