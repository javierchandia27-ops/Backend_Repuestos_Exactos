# Mercado Libre y alternativas guardadas

Validación inicial: 2026-10-31. Revisión de regresión: 2026-11-01. Rama: feat/integracion_api en los tres repositorios.

## Resultado comprobado

- OAuth Authorization Code con PKCE: autorización real completada por el operador.
- GET /users/me: 200 para la cuenta autorizada en MLC.
- GET /sites/MLC/search: 403 Forbidden, aun con credenciales y tokens válidos. No se ha confirmado la causa administrativa del rechazo.
- GET /products/search?site_id=MLC&status=active&q=...: 200. La prueba retornó referencias de catálogo con status=inactive, incluso solicitando active. El adaptador conserva el estado devuelto y no lo transforma en disponibilidad.
- El frontend muestra referencias técnicas sin precio, sin stock confirmado y sin enlace de compra inventado. Pueden guardarse como alternativa para revisión.
- Ofertas comerciales con precio y enlace: contrato y adaptador implementados y probados con respuestas controladas. No se pudieron validar ofertas comerciales reales con el acceso actual.
- No hay scraping, cambio de identidad, endpoint alternativo no documentado ni compras.

El catálogo técnico y la búsqueda de publicaciones son recursos distintos. Ante un 403 de publicaciones se utiliza el catálogo autorizado; el adaptador recuerda esa modalidad durante el proceso para no insistir en el recurso rechazado. Reiniciar la API permite volver a comprobar publicaciones cuando el proveedor habilite ese acceso.

## Flujo y responsabilidades

~~~mermaid
sequenceDiagram
  participant UI as Flutter
  participant API as Dart Frog
  participant DB as PostgreSQL/RLS
  participant ML as Mercado Libre
  UI->>API: GET /catalog/dtc/P0301/components
  API->>DB: Candidatos desde dtc_componente
  DB-->>UI: Componentes, sin depender de inventario local
  UI->>API: POST /offers/search (componente, modelo/año opcionales)
  API->>DB: Revalidar identidad y preparar consulta
  DB-->>API: Contexto validado; transacción cerrada
  API->>ML: Consulta con token privado
  ML-->>API: Publicaciones o referencias técnicas autorizadas
  API-->>UI: Resultados tipados y recibos temporales
  UI->>API: POST /saved-parts (recibo, nota, idempotencia)
  API->>DB: Revalidar identidad, insertar referencia y auditar
  DB-->>UI: Selección guardada
  UI->>API: GET /saved-parts
  API->>DB: Historial bajo RLS del taller
~~~

- routes adapta HTTP; dto valida JSON acotado; services coordina; repositories contiene SQL parametrizado; providers adapta la API oficial.
- /offers/search sigue autenticada. El middleware revalida la sesión en una transacción breve y el handler prepara el plan en otra; ambas terminan antes de esperar HTTP externo. No se agregó a publicPaths.
- Los widgets no consultan HTTP: OffersRepository → ApiOffersRepository → ApiClient. Los controladores descartan búsquedas tardías cuando cambia el contexto y conservan la clave de idempotencia al reintentar.
- El catálogo local y GET /sessions mantienen sus contratos.

## Contratos nuevos

| Ruta | Función |
| --- | --- |
| GET /catalog/dtc/{code}/components | Candidatos técnicos de una falla |
| POST /offers/search | Buscar en Mercado Libre con contexto validado |
| POST /saved-parts | Guardar una alternativa del resultado consultado |
| GET /saved-parts?limit=20&offset=0 | Historial de alternativas del taller |

Búsqueda:
~~~json
{"dtc":"P0301","component_id":"UUID_PUBLICO_COMPONENTE","model":"UUID_PUBLICO_MODELO","year":2016}
~~~
model/year son opcionales. vehicle_id permite asociar el vehículo registrado y exige su modelo/año correctos. session_id es opcional y exige que la falla pertenezca a ese diagnóstico y que el vehículo coincida. La pantalla manual usa contexto de vehículo cuando se identifica por VIN; el enlace desde un diagnóstico específico queda disponible en el contrato HTTP, todavía no en la navegación del historial.

Guardar:
~~~json
{"offer_token":"RECIBO_OPACO","idempotency_key":"UUID_NUEVO_POR_SOLICITUD","note":"Revisar compatibilidad y referencia del fabricante"}
~~~
No se reciben taller, autor, precio, stock ni URL desde el cliente. El recibo dura diez minutos, está ligado a usuario/taller y existe sólo en memoria del servidor. Tras reiniciar la API, se repite la búsqueda. Una selección ya guardada puede recuperarse con la misma idempotencia y solicitud, incluso si el recibo venció. Cambiar la nota requiere otra clave.

Tipos:
- kind=listing: publicación, precio decimal como string, moneda y URL HTTPS validada.
- kind=catalog_product: referencia técnica; price/currency/url son null; catalog_status refleja active/inactive. Un producto de catálogo no se presenta como oferta vendible.
- compatibility=unverified en ambos casos. Marca/modelo/año refinan palabras de búsqueda; no prueban compatibilidad mecánica, versión, motor ni aplicación de fabricante.

La primera página externa se limita a veinte resultados. No se ofrecen páginas adicionales de proveedor en este incremento. El historial propio usa páginas por offset y deduplicación en UI; las inserciones concurrentes pueden desplazar páginas y se recomienda actualizar para obtener el orden más reciente.

## Persistencia y permisos

V014 alinea nombres de restricciones/políticas, comentarios de columnas y borrado RESTRICT con las convenciones existentes, sin reescribir V013 ni modificar datos. V013 crea repuesto_guardado con taller, autor, DTC/componente, contexto opcional de vehículo/diagnóstico, proveedor, tipo, ID externo, enlace validado de publicación si existe, nota, idempotencia y fecha.

- Propietario y mecánico pueden guardar y leer alternativas de su taller.
- RLS ENABLE/FORCE, FK compuestas por taller y comprobación de autor en INSERT.
- FK DTC/componente y trigger para coherencia de diagnóstico/vehículo/modelo/año.
- Selecciones anexadas e inmutables en este incremento: no UPDATE ni DELETE para roles de aplicación.
- Trigger de auditoría; la nota y el enlace se excluyen del payload de auditoría.
- No se archivan títulos, imágenes, precios o stock externos. Se conserva la decisión y el identificador; no se congela contenido comercial como cotización.
- Guardar no cambia sesion_diagnostico.estado ni crea/cierra cotizacion.

La selección no equivale a diagnóstico confirmado, compra, reserva ni cotización formal. Para cotizar con un importe se requiere una publicación vigente autorizada o una fuente de precios disponible.

## Configuración privada

En .env del backend:
~~~dotenv
MELI_CLIENT_ID=
MELI_CLIENT_SECRET=
MELI_TOKEN_FILE=.secrets/mercadolibre-tokens.json
~~~
El Client Secret y los tokens nunca van al frontend, Git, logs, respuestas HTTP ni documentación. .env y .secrets/ están ignorados.

La instancia local ya fue autorizada. Para una autorización futura, desde la carpeta del backend:
~~~powershell
dart run bin/meli_authorize.dart --tunnel "C:\__apps\re-app\.repuestos-exactos\oauth-mercadolibre\cloudflared.exe"
~~~
El comando crea un receptor exclusivo en 127.0.0.1:8094, abre un túnel temporal y muestra el Redirect URI que debe registrarse exactamente en Mercado Libre. Tras guardarlo, Enter genera el enlace OAuth. El operador inicia sesión y autoriza; el código se valida con state y se intercambia usando PKCE. Al terminar se cierran receptor y túnel. No expone la API de negocio ni PostgreSQL.

Con HTTPS ya configurado hacia el receptor puede usarse MELI_REDIRECT_URI y ejecutar sin --tunnel. El puerto 8094 debe estar libre. No se requiere iniciar ese receptor para las búsquedas normales.

Renovación: se respeta expires_in, se serializa la renovación y se escribe el refresh token nuevo atómicamente. El archivo es para QA local con un solo proceso escritor. Varias réplicas requieren un almacén de secretos cifrado y coordinación distribuida; no se presenta este archivo como despliegue productivo.

## Verificación y evidencia

- 64 pruebas backend, incluidas integración PostgreSQL/HTTP y los nuevos casos de proveedor, recibos, JSON, idempotencia, auditoría y RLS.
- 47 pruebas frontend aprobadas; dos pruebas opcionales omitidas. Incluye respuesta tardía, reintentos, deserialización y tarjeta de referencia inactiva.
- dart analyze sin incidencias en ambos repositorios.
- V013 aplicada primero de forma transaccional en la base local con respaldo previo y validada también sobre copia restaurada. Un error inicial de permiso de creación del trigger revirtió toda la migración y se corrigió mediante permiso temporal dentro de la misma transacción.
- Flujo HTTP con catálogo real → guardar → repetir sin duplicar → listar → otro taller no ve la selección: validado en base temporal, posteriormente eliminada.
- UI de búsqueda real inspeccionada en Flutter web. El guardado HTTP se verificó en base aislada; no se afirma una prueba manual de guardado en el taller del usuario.
- Revisión del incremento: [correcciones y regresión](revision_incremento_20261101.md). Incluye 517 comprobaciones SQL aprobadas sobre copia aislada y V014 aplicada con respaldo previo.
- Evidencia inicial sin secretos: [validación](evidencia/integracion_mercadolibre_validacion.json).

## Referencias oficiales

- [Autenticación y autorización](https://developers.mercadolibre.cl/es_ar/como-empezar/autenticacion-y-autorizacion).
- [Buscador de productos de catálogo](https://developers.mercadolibre.com.ar/buscador-de-productos).
- [Términos del programa](https://developers.mercadolibre.cl/es_cl/terminos-y-condiciones).

El acceso a publicaciones comerciales permanece pendiente de habilitación/confirmación con Mercado Libre. Las respuestas observadas son evidencia de esta cuenta y fecha, no una garantía de acceso para otras aplicaciones.
