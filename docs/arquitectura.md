# Arquitectura de RE-api

RE-api es un monolito modular con Dart Frog: un proceso HTTP y módulos por capacidad del negocio. Este documento describe la estructura implementada, no carpetas futuras vacías.

## Responsabilidades

| Ubicación | Responsabilidad |
|---|---|
| main.dart | Arranque del pool, sesiones, CORS e inyección compartida |
| routes/ | Adaptadores HTTP y composición de dependencias por petición |
| lib/auth/ | Credenciales, sesiones y protección de rutas |
| lib/config/ | Configuración del entorno |
| lib/database/ | Pool, autenticación SQL y contexto transaccional por taller |
| lib/http/ | Errores públicos, CORS y metadatos de la petición |
| lib/features/diagnostics/models/ | Entidades y estados independientes de HTTP/PostgreSQL |
| lib/features/diagnostics/dto/ | Validación de filtros y serialización JSON |
| lib/features/diagnostics/services/ | Coordinación del historial y paginación |
| lib/features/diagnostics/repositories/ | Consultas SQL y mapeo a entidades |
| test/ | Pruebas de contratos, HTTP y base real |
| tool/ | Herramientas de diagnóstico local |

## Recorrido del historial

1. El middleware raíz resuelve el token y revalida usuario, taller y rol.
2. Abre una transacción y establece SET LOCAL ROLE y el contexto del taller.
3. El middleware de sessions construye DiagnosticRepository y DiagnosticService con esa transacción.
4. La ruta GET /sessions valida filtros mediante HistoryQuery.
5. El servicio comprueba el ancla de paginación y solicita limit + 1 registros.
6. El repositorio ejecuta SQL parametrizado del contrato q04 de RE-db, sujeto a RLS.
7. DiagnosticHistoryDto construye la respuesta sin identificadores internos.

El mismo TxSession se usa durante toda la solicitud; los repositorios no abren conexiones nuevas ni toman taller/rol desde el cliente. Los modelos no importan Dart Frog ni postgres. El servicio recibe filtros tipados, no RequestContext.

## Reglas para ampliar módulos

- Colocar las consultas nuevas en el repositorio de la capacidad correspondiente.
- Mantener las reglas de negocio en servicios y los detalles HTTP en rutas/DTO.
- Inyectar dependencias; evitar conexiones y estados globales dentro de módulos.
- Agregar interfaces o capas adicionales cuando permitan sustituir una dependencia o aislar una regla concreta.
- Catálogo y vehículos ya tienen sus primeros casos funcionales. Crear cotizaciones al implementar su primer caso.
- Las tablas, permisos y migraciones siguen en RE-db; las clases Dart no modifican el esquema.
- lib/src es una convención útil para implementación interna de paquetes. Esta aplicación conserva lib/ para mantener sus imports actuales; no constituye una frontera de seguridad.

## Alcance actual

Diagnósticos implementa la lectura del historial. Catálogo implementa marcas, modelos, códigos DTC y repuestos filtrados; vehículos implementa identificación local por VIN. Contrato: [busqueda.md](busqueda.md). Autenticación conserva su integración SQL en Database y GET /settings conserva su consulta pequeña en la ruta existente. Su separación futura se hará al ampliar esos casos, manteniendo contratos y pruebas.

Flutter mantiene su organización presentation/domain/data. El historial usa pantalla → HistoryController → HistoryRepository → ApiHistoryRepository → ApiClient/Dio. La vista no ejecuta HTTP ni SQL. Sus datos viven en el controlador de la ruta y se descartan al salir; las respuestas tardías se ignoran tras cambiar filtros o destruir el controlador.
