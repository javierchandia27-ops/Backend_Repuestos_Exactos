# Búsqueda de vehículos y repuestos

## Rutas autenticadas

| Método y ruta | Uso y permisos |
|---|---|
| GET /catalog/brands | Marcas globales; admin, mecanico y auditor |
| GET /catalog/brands/{marca}/models | Modelos de una marca pública; los tres roles |
| GET /catalog/dtc?q=P03&limit=20 | Búsqueda por prefijo DTC; los tres roles |
| GET /catalog/dtc/{codigo}/parts | Repuestos asociados al DTC y precios del taller; los tres roles |
| GET /search?vin=... | Vehículo registrado en el taller; admin y mecanico |

Todas las rutas heredan token, revalidación del usuario, transacción con rol y contexto de taller, RLS, errores públicos y CORS. No aceptan un taller, usuario o rol enviado por el cliente. Las consultas nuevas solo leen datos.

## Catálogo

Las consultas siguen RE-db/db/queries/q02_configuracion_y_catalogos.sql. Marcas y modelos devuelven data con id_publico y nombre. Una marca válida sin modelos devuelve una lista vacía.

La búsqueda DTC normaliza mayúsculas y espacios exteriores. Acepta prefijos válidos de hasta cinco caracteres; vacío lista los primeros códigos. Rechaza comodines SQL y prefijos ajenos al formato PCBU. limit va de 1 a 100. Devuelve data con codigo, descripcion, severidad_sugerida y componentes, además de has_more para pedir un prefijo más específico.

Los repuestos requieren un DTC completo existente. Parámetros: model (UUID opcional), year (1981–2100, requiere model), limit (1–100, por defecto 20) y offset (0–1000000, por defecto 0). La respuesta contiene data y next_offset, null al terminar. La paginación por posición se aplica al catálogo ordenado por componente, perfil genuino/oem/generico, precio e ID. Si cambia el catálogo entre peticiones no constituye una instantánea histórica; cambiar filtros reinicia la búsqueda.

Con model y year se aplica RN-44 mediante EXISTS sobre rangos de compatibilidad, evitando duplicados por rangos superpuestos. Sin vehículo se devuelve catálogo general asociado al DTC y no se afirma compatibilidad individual. Un código conocido sin repuestos compatibles devuelve 200 vacío; un código inexistente devuelve 404 dtc_not_found.

RN-45 calcula ROUND(precio_referencia * (1 + margen_pct / 100)) con la configuración del taller autenticado. La API devuelve precio_venta como cadena entera decimal para conservar precisión en Flutter web; no expone el precio base. La moneda viene de taller_configuracion. Es un precio de referencia del catálogo con margen, no una cotización guardada ni una consulta a proveedores externos.

## VIN local

GET /search acepta exclusivamente un VIN exacto de 17 caracteres, normalizado a mayúsculas, sin I, O ni Q. Usa una proyección mínima de q03_vehiculos: devuelve UUID del vehículo, VIN, patente, año, marca y modelo con UUID públicos. No lee ni devuelve nombres u otros datos del titular.

No encontrar un vehículo visible devuelve 200 con data null, tanto si no existe como si está fuera del contexto o queda oculto por RLS. El rol auditor recibe 403 vehicle_search_forbidden antes de consultar vehículos, conservando la separación funcional de q03.

No hay decodificación externa de VIN ni alta automática de vehículos. La consulta solo completa modelo y año desde un vehículo ya registrado y visible.

## Organización

- lib/features/catalog: modelos, DTO, servicio y repositorio de marcas/modelos/DTC/repuestos.
- lib/features/vehicles: modelo, DTO, servicio y repositorio del vehículo encontrado.
- lib/http/query_validation.dart: validación común de parámetros, enteros, UUID y DTC.
- routes/catalog/_middleware.dart: composición del módulo con la misma transacción de la petición.
- routes/search.dart: validación HTTP y restricción de rol para VIN.

Las tablas y migraciones permanecen en RE-db. La configuración de conexión, autenticación e historial mantienen sus contratos.

## Validación

Las pruebas HTTP reales usan los dos talleres y los tres roles del seed. Comprueban filtros, paginación sin duplicados, precios distintos por margen, VIN de otro taller, vehículos ocultos al mecánico, prohibición para auditor y rechazo de parámetros manipulados. Las credenciales se leen del entorno local y nunca se escriben en el repositorio. Las pruebas generan la auditoría habitual del login sin modificar datos de negocio.
