# Revisión del incremento Mercado Libre

Fecha: 2026-11-01. Tres repositorios en feat/integracion_api. Cambios sin commit ni push.

## Dictamen

Listo para versionar como incremento de QA de búsqueda externa y alternativas guardadas, con las correcciones indicadas abajo. No se encontraron regresiones en los flujos ejecutados. La revisión combina lectura del diff, análisis estático, pruebas de widgets/controladores y pruebas HTTP/PostgreSQL; no garantiza ausencia de errores fuera de esa cobertura.

## Correcciones realizadas en esta revisión

1. El diálogo Guardar alternativa desbordaba 393 px en una pantalla de 375×667 con teclado de 300 px. Se hizo desplazable. La nueva prueba de widget falló antes del cambio y pasa después.
2. Si el año del vehículo cambiaba entre consultar y guardar, la restricción SQL rechazaba correctamente la selección, pero el backend devolvía database_unavailable. El repositorio transforma las infracciones de contexto 23503/23514 en HTTP 409 invalid_saved_context; otros errores se propagan. La prueba usa PostgreSQL y revierte el cambio del vehículo.
3. V013 no cumplía todas las convenciones del esquema: restricciones con nombres automáticos, FK sin RESTRICT explícito, columnas sin comentarios y nombres de políticas distintos al patrón. V014 lo corrige sin editar una migración ya aplicada. Las pruebas conservan las invariantes y actualizan únicamente los conteos de objetos por la nueva tabla. V014 se probó en una copia aislada y se aplicó a la base local en una sola transacción, con respaldo previo; no modifica filas de negocio.

## Resultado de verificaciones

| Comprobación | Resultado |
| --- | --- |
| Flutter test | 47 aprobadas, 2 opcionales omitidas |
| Dart test backend con DB y HTTP habilitados | 64 aprobadas |
| Doce archivos SQL db/tests/01–12 | 517 PASS, 0 FAIL; errores esperados coinciden con sus aserciones |
| Análisis Flutter | Sin incidencias |
| Análisis backend, incluyendo infos | Sin incidencias |
| Git diff --check | Sin errores de whitespace |

El SQL y las pruebas HTTP se ejecutaron contra una base temporal restaurada desde la local. El servidor HTTP de revisión usó los handlers/router de Dart Frog, autenticación, transacciones y RLS reales, con respuestas de Mercado Libre controladas. La llamada real al proveedor fue validada en la evidencia inicial del incremento; esta regresión no depende de una nueva autorización externa.

Se comprobaron login/logout, roles de propietario/mecánico, onboarding y configuración con las pruebas existentes; catálogo local, VIN y compatibilidad; historial de diagnósticos y paginación; búsqueda externa, guardado, reintentos sin duplicación, conflictos de idempotencia, rechazo de campos forjados y aislamiento entre talleres. La prueba HTTP comprueba que GET /sessions conserva exactamente su respuesta después de guardar alternativas. Guardar no crea cotizaciones ni cambia estados de diagnóstico.

Las dos pruebas Flutter omitidas requieren configuración opcional de integración real. No se ejecutaron en esta revisión los runners shell concurrencia.sh/operacion.sh ni una autenticación interactiva nueva de Google.

## Patrón preservado

- Flutter: presentación y controladores → contrato de dominio → repositorio de datos → ApiClient. Sin SQL ni llamadas al proveedor desde widgets.
- Backend: rutas HTTP → DTO/servicio → repositorio SQL o adaptador externo. La consulta a Mercado Libre ocurre después de liberar las transacciones SQL; la ruta permanece autenticada.
- PostgreSQL: RLS ENABLE/FORCE, autor/taller derivados de sesión, claves compuestas, permisos mínimos, auditoría e idempotencia. La referencia guardada no conserva precios, títulos ni stock comercial.
- No se cambian los contratos del catálogo local ni GET /sessions. El historial de alternativas tiene su propia ruta.

## Repetir validaciones

Desde cada repositorio se pueden ejecutar flutter analyze / flutter test y dart analyze --fatal-infos / dart test. Sin variables optativas, las integraciones se omiten deliberadamente.

Para habilitar las pruebas DB: RUN_DATABASE_TESTS=true y RE_DB_ENV_FILE apuntando al .env privado de RE-db. Para HTTP: TEST_API_URL debe apuntar a una API que use la misma copia de PostgreSQL que DB_NAME. RUN_OFFERS_HTTP_TESTS=true habilita el recorrido nuevo, que guarda referencias y por eso exige un nombre de base con prefijo re_api_preflight_. Ejecutar sólo sobre una copia desechable con semillas y migraciones hasta V014. Para repetir contra el proveedor real se necesitan sus credenciales y autorización vigentes; su disponibilidad no es una aserción de los tests unitarios.

## Límites que conserva el incremento

- Mercado Libre rechaza la búsqueda de publicaciones con 403 para el acceso actual. El fallback consulta catálogo técnico y muestra expresamente referencias sin precio ni stock confirmado. No equivale a una cotización comercial completa.
- Compatibilidad pendiente de revisión técnica, incluso con modelo y año.
- Recibos de búsqueda en memoria; despliegue QA de un proceso. Reiniciar requiere buscar de nuevo, salvo reintento idempotente de una selección ya guardada.
- El escáner Bluetooth/OBD2 sigue siendo prototipo; no se validó hardware ni se implementó captura en este incremento.
- El vínculo session_id está soportado por HTTP; la navegación desde un diagnóstico específico sigue pendiente. La búsqueda manual y el historial independiente de alternativas funcionan.
