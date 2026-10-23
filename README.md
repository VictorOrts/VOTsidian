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

- Al abrir la app (y antes del primer cambio de cada día) se copia toda la carpeta a la carpeta de copias. Si una copia falla, o la última tiene más de 2 días, sale un aviso.
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

Las copias van a `~/Library/Application Support/VOTsidian/Copias` (Ajustes → «Ver copias en Finder»), fuera de Documentos para que no ocupen iCloud; las que había en `~/Documents/Copias VOTsidian` se mueven solas al abrir. La app conserva las últimas 14 automáticas (`…-auto-AAAA-MM-DD`) y borra las más viejas; las manuales (`…-manual-…`) no se borran solas.

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
- **Exportar** (Ajustes): resumen del año en PDF, datos en CSV (peso, pinchazos, medidas, hábitos, tareas, gastos, ánimo y sueño) y todas las notas en .zip.
- **Rendimiento**: la app solo vuelve a leer los archivos que cambian y vigila la carpeta con FSEvents (recarga al instante cuando algo cambia fuera).

- **Peso**: la fecha estimada de llegada usa la tendencia suavizada y muestra un rango (ritmo de 2 meses, 4 meses o todo el historial), también dibujado en la gráfica.
- **Bases**: filtros por propiedad (contiene, es, no es, vacía, con valor), orden pulsando la cabecera y vistas guardadas por tipo (menú «Vistas»).
- **Notas**: «Enlazada desde» muestra la línea que enlaza, y al pasar el ratón sobre un enlace del panel sale una vista previa de esa nota.

- **Fiabilidad** (octubre 2026): las fechas imposibles («31/2», «el 31» en un mes de 30 días) ya no se convierten en otra fecha; al cerrar la app (⌘Q) se guarda lo que el autoguardado aún no había guardado; renombrar una nota actualiza también los enlaces con carpeta (`[[Salud/Médico]]`) o con otras tildes y mayúsculas; borrar una nota no quita los enlaces si queda otra con el mismo nombre; el grafo se actualiza al añadir enlaces; las notas con saltos de línea de Windows se leen bien; los avisos del sistema se reprograman cada día aunque la app siga abierta.

- **Gastos** (octubre 2026): «Puedes gastar hoy» resta lo gastado hoy (antes un gasto grande apenas lo movía); devoluciones («devolución 30 Zara», «reembolso 15 Amazon») restan de su partida («abono transporte 20» sigue siendo un gasto); doble clic en un movimiento para corregir importe, fecha o nota (con fecha de otro mes pasa a esa nota); buscador y total en Movimientos; los movimientos con una partida que no está en la tabla dicen cuál es y se puede crear con un clic; un pago marcado antes de su día ya no cuenta en «Hoy quedan»; la meta del fondo usa un mes típico (el seguro anual cuenta 1/12 cada mes); al cerrar un mes, los fijos sin marcar se avisan y no se pasan al fondo, y la primera quincena del mes siguiente ese cierre sale también en el mes en curso; al corregir una partida ya no se aprenden palabras que son de otra partida («seguro»), y renombrar una partida conserva lo aprendido; «2 cafés 3,50» toma 3,50 y «€12 pan» deja la nota limpia; deshacer el primer gasto de un mes quita también la nota creada; `gastos.csv` en la exportación.

- **Gastos → Año**: resumen anual sacado de las notas de cada mes, con mes, ingresos, gastos (sin el ahorro) y lo que queda. Tiene una gráfica de barras por mes (al pasar el ratón por un mes salen sus cifras) y una tabla; pulsar un mes lo abre. «Guardar en nota» deja la tabla en `Finanzas/Gastos/Resumen AAAA.md`, con enlaces a cada mes; al actualizarla se conserva lo que escribas en «## Comentarios», y la app avisa si la nota se ha quedado atrás. Un mes creado por adelantado sale como «previsto», con lo previsto de cada partida (o lo ya pagado, si es más).

- **Gastos y Finanzas** (más): si el mes actual no tiene nota pero otro sí (p. ej. noviembre preparado en octubre), Gastos, Inicio y Finanzas ofrecen «Ver noviembre»; Finanzas resume el año («En 2026: ingresos · gastos · queda») con un botón al resumen; una aportación de evento se da por pagada con un clic («Ya pagada: apuntar en Gastos»), que la apunta como gasto y pone el evento en pagado (se deshace de una vez); en Ingresos se pueden añadir y quitar conceptos; aviso de partidas con 0 € previstos; la exportación incluye `resumen_mensual.csv`.
- **Gastos → Año** (acabado): tasa de ahorro por mes y del año (lo que queda sobre lo que entró) y lo apartado en partidas de ahorro; «Gastos frente a 2025» compara los meses acabados con los mismos del año anterior; línea discontinua con el gasto medio en la gráfica; tarjeta «Por partida» con previsto, gastado, diferencia y peso de cada partida en el año (las 8 principales o todas). La nota del resumen incluye la columna «% ahorro» y la sección «## Por partida», y la exportación añade `resumen_partidas.csv`.
- **Detalles visuales**: fechas con año cuando no son de este año (tareas, avisos, notas, Bases); «1 día», «1 pinchazo», «1 evento» en singular; la leyenda del Calendario ya no parte «pinchazo» y baja de línea si no cabe; los selectores Tablas/Tablero y Lista/Tablero quedan alineados.

## Recuperar versiones y enlaces rotos

- **Historial de una nota** (Notas → ⋯ → Historial…): cada versión distinta de la nota en las copias de seguridad, comparada línea a línea con la actual (rojo: estaba y ya no; verde: añadido después). «Restaurar esta versión» se deshace con ⌥⌘Z. Las copias cifradas se abren con la contraseña del Llavero; las de otra contraseña se cuentan aparte.
- **Restaurar una copia entera** (Ajustes → Copias de seguridad): lista de copias con «Abrir» (Finder; las cifradas piden la contraseña) y «Restaurar…». Antes de restaurar se guarda una copia `…-antes-de-restaurar` del estado actual, que es la forma de volver atrás. Las notas creadas después de la copia se conservan.
- **Enlaces rotos** (Conocimiento → Enlaces rotos): los `[[…]]` que no llevan a ninguna nota, agrupados por nota, con hasta tres notas de nombre parecido para cambiar el enlace con un clic, «Crear nota» (en la misma carpeta) y la lista de notas sin ningún enlace.

## Órdenes rápidas (⌘K)

Escribe una orden y pulsa intro: `peso 105,5` · `peso 105,5 ayer` · `ánimo 4` · `dormí 7,5` · `pinchazo hoy` · `tarea llamar al dentista el viernes urgente` · `idea …` · `nota …` (a la nota de hoy) · `cita endocrino el 29/10` · `cintura 98,5` · `compra leche, huevos y pan`.

## Compra y mantenimiento

- **Compra**: lista con casillas por secciones (`Cambio físico/Lista de la compra.md`), se genera desde la sección «Lista de la compra» de Menú y compra. No cuenta como tareas.
- **Casa → Mantenimiento del hogar**: sugerencias según tus aparatos (lavadora, lavavajillas, cafetera…) que se añaden como tareas que se repiten solas.

## Planificar la semana

- **Planificar semana**: tablero de lunes a domingo; arrastra tareas entre días, a «Sin fecha» o desde «Vencidas». Marca los días con más de 5 tareas.

## Avisos del sistema y conflictos de iCloud

- **Avisos → «Avisos del sistema»**: programa notificaciones de macOS para los próximos 30 días (máx. 60) con el mismo plan que el calendario. Solo funcionan en la app (`./scripts/build-app.sh`), no con `swift run`. Se reprograman al abrir la app.
- **Conflictos de iCloud**: si aparece `Nota 2.md` junto a `Nota.md` (o una «copia en conflicto»), sale un aviso en Inicio/Avisos para que compares y borres una.

## Otra estructura de carpetas

Las rutas de los archivos que usa cada pantalla (peso, Mounjaro, Inbox…) están en `VaultPath`. Para cambiar una sin tocar código:

```bash
defaults write com.victor.votsidian vaultPathOverrides -dict peso "Salud/Peso.md" inbox "Bandeja.md"
```

Claves: peso, mounjaro, plan, proyecto, nala, casa, moda, medico, inbox, documentos, personas, objetivos, finanzas, gastos, revisiones, compra, medidas. Una carpeta es válida si tiene el archivo de peso o cualquier nota; las pantallas sin su archivo salen vacías.

## Estructura del código

`Store` (estado de la app) se reparte en extensiones: `Store+Scan` (leer la carpeta, también en segundo plano), `Store+Writing` (escritura y copias), `Store+Undo`, `Store+Links`, `Store+Notes`, etc. Los modelos y parsers están en `Models`, `Parsers`, `CasaEnlaces`, `Tablas` y `Medidas`; las ediciones puras de texto en `Edits` y `Templates`.

## Próximas funcionalidades

Ideas pendientes, por orden de prioridad:

1. **Atajos y Siri (App Intents)**: «Anotar peso», «Añadir tarea» o «Pinchazo hoy» desde Atajos, reutilizando las órdenes rápidas de ⌘K. Solo en la app compilada con `build-app.sh`.
2. **Plantilla del diario**: `Plantillas/Diario.md` se aplica al crear la nota de cada día.
3. **Tareas con hora** (`⏰ 10:30`): el aviso del sistema salta a esa hora y no a las 9.
4. **Citas del Calendario de macOS** (EventKit) en Inicio y en la barra de menús, junto a las tareas del vault.
