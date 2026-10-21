# VOTsidian

App nativa de macOS (SwiftUI) para llevar peso, Mounjaro, hábitos, revisiones, tareas, calendario, casa, salud y notas sobre una carpeta de archivos Markdown. No necesita Obsidian: lee y escribe los mismos archivos.

## Usar

```bash
swift run VOTsidian          # desde la terminal
./scripts/build-app.sh       # crea build/VOTsidian.app (con icono) para abrir con doble clic
swift test                   # tests
```

La carpeta de notas por defecto es `iCloud Drive/VOTsidian`. Se cambia en Ajustes.

## Seguridad de los datos

- Antes del primer cambio de cada día se copia toda la carpeta a `~/Documents/<carpeta>-backup-AAAA-MM-DD`.
- Cada cambio se puede deshacer (⌥⌘Z o el botón del aviso).
- Los tests de escritura trabajan sobre copias temporales. Para probar con tus notas: `VAULT_COPY=/ruta/a/una/copia swift test`.

## Atajos

⌘K buscar · ⇧⌘N captura rápida · ⌘1…⌘9 pantallas · ⌘S guardar · ⌥⌘Z deshacer.

## Fechas en lenguaje natural

En la captura rápida, el calendario y Inicio: «llamar al dentista el viernes», «pagar 25/11», «revisar en 3 días», «pagar el alquiler cada mes» (se repite).

## Guardado

Lo que escribes se guarda solo 1,5 s después de dejar de teclear (notas, revisiones, nota del día, propiedades). Los guardados automáticos seguidos se deshacen de una vez. Si una nota cambia fuera de la app mientras la editas, la app avisa en vez de pisarla.

## Buscar (⌘K)

Filtros por tipo (pantallas, notas, tareas, texto), por carpeta y, para tareas, por fecha (vencidas, hoy, 7 días, sin fecha). Flechas ↑↓ para moverse e intro para abrir.

Las copias van a `~/Documents/Copias VOTsidian`. La app conserva las últimas 14 automáticas (`…-auto-AAAA-MM-DD`) y borra las más viejas; las manuales (`…-manual-…`) no se borran solas.

## Qué hay dentro (resumen)

Inicio · Tareas (prioridad, repetición, fechas en lenguaje natural) · Calendario con nota del día, ánimo y sueño · Revisión semanal y mensual · Proyectos, Casa y Moda con vista de lista y de tablero (arrastra para cambiar de estado) · Peso, medidas y fotos · Mounjaro · Salud y médicos · Notas con etiquetas, fijadas, menciones sin enlazar, plantillas propias (carpeta `Plantillas`), exportar a PDF · Bases (tabla de propiedades por tipo) · Grafo · Cerrar el día · ⌘K.

## Notas: pestañas y autocompletado

Varias notas abiertas a la vez: pestañas arriba (⌘T nueva, ⌘W cerrar, ⇧⌘[ y ⇧⌘] para cambiar; clic derecho en la lista para abrir en pestaña nueva; ⌘+clic en un enlace lo abre en otra pestaña). Las pestañas se recuerdan al reabrir la app. Al editar, `[[` sugiere notas (y ofrece crear la que no existe) y `#` sugiere etiquetas; ↑↓ para elegir, intro o tab para insertar, esc para cerrar.

## Novedades recientes

- **Búsqueda (⌘K)**: varias palabras a la vez, sinónimos (médico = doctor = cita…), operadores `#etiqueta`, `carpeta:casa`, `tipo:evento`, fechas («el viernes» muestra lo de ese día) y resaltado de lo encontrado.
- **Notas**: `![[Nota]]` y `![[Nota#Sección]]` muestran el contenido de otra nota; `![[imagen.png]]` muestra una imagen.
- **Plantillas con preguntas**: en `Plantillas/`, `{{?Destino}}` o `{{?Estado|pendiente}}` piden el dato al crear la nota.
- **Inicio personalizable**: botón «Personalizar» para reordenar y ocultar tarjetas.
- **Barra de menús**: panel con peso, pinchazo, tareas de hoy (marcables), hábitos de hoy, ánimo y añadir tareas.
- **Exportar** (Ajustes): resumen del año en PDF, datos en CSV (peso, pinchazos, medidas, hábitos, tareas, ánimo y sueño) y todas las notas en .zip.
- **Rendimiento**: la app solo vuelve a leer los archivos que cambian y vigila la carpeta con FSEvents (recarga al instante cuando algo cambia fuera).

- **Peso**: la fecha estimada de llegada usa la tendencia suavizada y muestra un rango (ritmo de 2 meses, 4 meses o todo el historial), también dibujado en la gráfica.
- **Bases**: filtros por propiedad (contiene, es, no es, vacía, con valor), orden pulsando la cabecera y vistas guardadas por tipo (menú «Vistas»).
- **Notas**: «Enlazada desde» muestra la línea que enlaza, y al pasar el ratón sobre un enlace del panel sale una vista previa de esa nota.

## Órdenes rápidas (⌘K)

Escribe una orden y pulsa intro: `peso 105,5` · `peso 105,5 ayer` · `ánimo 4` · `dormí 7,5` · `pinchazo hoy` · `tarea llamar al dentista el viernes urgente` · `idea …` · `nota …` (a la nota de hoy) · `cita endocrino el 29/10` · `cintura 98,5` · `compra leche, huevos y pan`.

## Compra y mantenimiento

- **Compra**: lista con casillas por secciones (`Cambio físico/Lista de la compra.md`), se genera desde la sección «Lista de la compra» de Menú y compra. No cuenta como tareas.
- **Casa → Mantenimiento del hogar**: sugerencias según tus aparatos (lavadora, lavavajillas, cafetera…) que se añaden como tareas que se repiten solas.

## Planificar la semana y analíticas

- **Planificar semana**: tablero de lunes a domingo; arrastra tareas entre días, a «Sin fecha» o desde «Vencidas». Marca los días con más de 5 tareas.
- **Analíticas** (Cuerpo): cada valor de tus análisis con unidad y referencia en `Organización/Médico/Analíticas.md`; avisa de lo que queda fuera de rango, dibuja la evolución con su banda de referencia y lo añade al resumen para el médico.

## Avisos del sistema y conflictos de iCloud

- **Avisos → «Avisos del sistema»**: programa notificaciones de macOS para los próximos 30 días (máx. 60) con el mismo plan que el calendario. Solo funcionan en la app (`./scripts/build-app.sh`), no con `swift run`. Se reprograman al abrir la app.
- **Conflictos de iCloud**: si aparece `Nota 2.md` junto a `Nota.md` (o una «copia en conflicto»), sale un aviso en Inicio/Avisos para que compares y borres una.

## Otra estructura de carpetas

Las rutas de los archivos que usa cada pantalla (peso, Mounjaro, Inbox…) están en `VaultPath`. Para cambiar una sin tocar código:

```bash
defaults write com.victor.votsidian vaultPathOverrides -dict peso "Salud/Peso.md" inbox "Bandeja.md"
```

Claves: peso, mounjaro, plan, proyecto, nala, casa, moda, medico, inbox, documentos, personas, objetivos, finanzas, revisiones. Una carpeta es válida si tiene el archivo de peso o cualquier nota; las pantallas sin su archivo salen vacías.

## Estructura del código

`Store` (estado de la app) se reparte en extensiones: `Store+Scan` (leer la carpeta, también en segundo plano), `Store+Writing` (escritura y copias), `Store+Undo`, `Store+Links`, `Store+Notes`, etc. Los modelos y parsers están en `Models`, `Parsers`, `CasaEnlaces`, `Tablas` y `Medidas`; las ediciones puras de texto en `Edits` y `Templates`.
