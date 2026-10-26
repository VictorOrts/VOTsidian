# VOTsidian: notas para trabajar en el código

Agenda personal para macOS 26 en SwiftUI (paquete Swift 6.3, sin dependencias). Todo se guarda en notas Markdown de una carpeta
del usuario, compatible con Obsidian: **las notas son la fuente de verdad**, no hay base de datos. Interfaz, comentarios,
mensajes de commit y documentación, en español. Formato de cada nota para el usuario: [GUIA.md](GUIA.md).

## Comandos

```bash
swift build                                    # compilar
swift test                                     # ~250 tests, ~50 s (incluye fuzz)
./scripts/build-app.sh                         # build/VOTsidian.app (release, firmada)
VOT_SHOTS=.claude/capturas VOT_SHOT_SCREEN=vehiculo VOT_SHOT_HEIGHT=1500 swift test --filter screenshots   # captura de una pantalla
VOT_FUZZ=10 VOT_FUZZ_SEED=3 swift test --filter FuzzTests                                               # fuzz a fondo
VOT_BENCH=1 swift test -c release --filter heavyUserBenchmark                                            # tiempos con 3 años de datos
VOT_BENCH=1 VOT_BENCH_SCREEN=calendario swift test -c release --filter heavyUserBenchmark                # pinta esa pantalla 20 s (para `sample <pid>`)
SWIFT_BACKTRACE=enable=yes,color=no,interactive=no,symbolicate=full swift test --filter X                # traza si un test cierra el proceso
```

- `VOT_SCREEN=vehiculo` abre la app en esa pantalla. `VAULT_COPY=/ruta` hace que los tests de humo usen una copia de notas reales.
- Capturas de referencia de todas las pantallas (vault sintético, modo claro): `.claude/capturas/` (fuera de git).
  El modo oscuro sale con el texto invisible en la herramienta de capturas: es una limitación suya, también en `master`.

## Arquitectura

- Carpetas de `Sources/VOTsidian/`: `App` (ventana, barra lateral, ⌘K, Ajustes), `Store` (`Store` y sus extensiones, módulos,
  copias), `Formato` (`Parse`, `Edit`, `MD`, `NaturalDate`: lo puro), `UI` (componentes), `Planificacion`, `Avisos`,
  `Conocimiento` (Notas, Bases, Grafo, Lienzo) y `Modulos/<sección>`. SwiftPM recoge las subcarpetas solo: mover un archivo no
  cambia nada del código. Sin tildes en los nombres de carpeta.

- `Store` (`@MainActor @Observable`, en `Store.swift` y `Store+*.swift`): estado publicado y acciones. `VaultPath` da la ruta de
  cada nota por clave (`"vehiculo"` → `Vehículo/Vehículo.md`), configurable en Ajustes.
- `Parse` (leer) y `Edit` (transformar texto → `String?`) son enums de funciones puras: ahí va la lógica, y es lo que se testea.
- Escribir: `store.edit(rel) { Edit.algo($0) }` lee del disco, aplica, escribe atómico, apunta el deshacer y recarga solo esa nota
  (`reload(changed:)`). Si la nota de un módulo no existe, parte de su plantilla (`Starter.text(forKey:)`).
  `grouped { … }` junta varios cambios en un solo deshacer (p. ej. nota del módulo + gasto en Gastos).
- `apply(scan)` publica todo; cada módulo se analiza con `derive(VaultPath.x) { x = Parse.x($0) }` solo si su texto cambió.
- Avisos: `alerts()` (`Alerts.swift`), filtrados por módulo visible. Calendario: `buildAgenda` (`Agenda.swift`), también filtrado.
  Calendar/notificaciones: `ICS.events` (`Reminders.swift`) → `.ics`, `Notifier` o EventKit (`CalendarSync.swift`, opcional).
- Gastos desde otros módulos: `addLinkedExpense(_:note:date:category:fallback:)` (`Store+Gastos.swift`).
- Lienzo (`.canvas` de Obsidian): `JSONCanvas` (puro, con `JSONSerialization` para conservar campos desconocidos) y `LienzoView`.
  Los `.canvas` no son notas: no entran en el escaneo, `reload(changed:)` solo sube `canvasStamp` y la lista sale de `canvasFiles()`.
- Módulos ocultos: `hiddenModules`; los nuevos se ocultan solos en carpetas ya configuradas (`registerNewModules`, `knownModules`).
- Ventana (`ContentView.swift`): `ScreenView` pinta una pantalla (la usan también las ventanas aparte, `WindowGroup` «pantalla» y
  «nota» en `VOTsidianApp`). Mi día, Planificar y Tareas son los modos de la Agenda (`Screen.agendaModes`, una fila en la barra;
  `store.go(_:)` vuelve al último modo). Fijadas: `Pins` (`@AppStorage("pinnedScreens")`, también ⌘2…⌘9). Historial: `backStack`/
  `forwardStack` en `screen.didSet` (`Store+Navegacion.swift`, con el enfoque `FocusSession`).
- Panel derecho: `HoyPanel` (`Planificacion/HoyPanel.swift`), con `NotePeek` para `store.peekNote` (enlaces abiertos al lado:
  `open(link:peek:)`). Captura: `Capture.interpret` (puro, `App/Capture.swift`) → `CaptureGuess` (orden + etiquetas + nota);
  `CaptureField` es el campo de añadir tareas de todas las pantallas y guarda con `store.run`.

## Añadir un módulo (todos los puntos)

1. `Sources/VOTsidian/Modulos/<sección>/X.swift` (Cuerpo, Dinero, Hogar u Ocio, como la barra lateral): modelo `XData`, `Parse.x`, `Edit.addX…` (con `Edit.addRow(text, section:)`), acciones en `extension Store`,
   y `xAlerts(today:)` si avisa. `XView.swift`: la pantalla (`MissingNoteBanner`, `Tile`, `Card`, `AlertList(alerts:emptyText:)`, `NoteTables`).
2. `Store.swift`: `VaultPath.defaults` + `static var x`, comentario de claves, `private(set) var x = XData()`, `derive(VaultPath.x)`.
3. `ContentView.swift`: `Screen` (case + icono + sección en `Screen.sections` + vista en `ScreenView`).
4. `Modules.swift`: `Module` (case, `title`, `detail`, `icon`, `screens`, `files`), `Starter.labels`, plantilla en `Starter.text`.
5. `Store+Derived.swift`: `reminderSources()` y el mapa de pantallas de `open(link:)`.
6. `Alerts.swift` (`out += xAlerts…`), `Agenda.swift` (`Kind` con icono y color, elementos, `screenAliases`), `SearchEngine.swift` (sinónimos).
7. `Reminders.swift` (`ReminderPlan` var al final + `stored` + `ReminderSources` + eventos `ICS`) y `RemindersView.swift` (`@AppStorage`, init del plan, fila).
8. Inicio: `HomeCard` (case, título, módulo, vista). Exportar: `Export.swift` (`exportModules`).
9. Tests: caso en `renderAllScreens` (`ScreenSmokeTests.swift`), fixture en `syntheticVault()` (`TestSupport.swift`), tests propios,
   operación en `everyOperationIsUndoneExactly` y lector en `readEverything` (`FuzzTests.swift`). Al añadir un módulo cambian
   `Module.arrivals`/`original` y el número de `HomeCard` en sus tests.
10. README (tabla de módulos) y GUIA (ruta, formato de fechas, formato de la nota y avisos).

## Trampas conocidas

- `MD.section(lines, containing:)` coge el **primer** encabezado que contenga la clave: el título de la nota (`# Suscripciones`) no
  puede contener el nombre de la sección de la tabla (por eso `## Servicios`, `## Lo que debo`, `## Destinos`).
- Números de notas: `MD.number` (cifras ASCII, nunca infinito) y `MD.int` (nunca `Int(Double)`: un número enorme cierra la app).
  Importes con `Money.parse`, nunca `Double(texto)` a pelo: acepta «nan», «inf» y «1e999». Insertar líneas
  con `insertClamped`. Plegar texto conservando posiciones con `NaturalDate.aligned`. Fechas con `[0-9]`, no `\d`.
- Las notas con `tipo: compra` o `tipo: viajes` no aportan tareas (`Store.notTaskTypes`).
- Marcadores de tarea propios, además de los de Obsidian Tasks: `⏰ 17:30` (hora, tras la fecha), `⏱ 1h30m` (duración,
  `TaskDuration`) y `🔕` (no va a Calendar ni a las notificaciones). Se escriben con `Edit.taskLine`/`dueMark`/`durationMark` y se
  conservan en `updateTask` y `completeRecurring`. Un emoji con selector de variación (`⏱️`) no lo encuentra `String.range(of:)`
  con regex ni un literal `/⏱/`: buscar con `NSString` (ver `TaskDuration.find` y `Recurrence.find`).
- Mi día (`MiDia.swift`, `MiDiaView.swift`): `DayPlan.build` (puro) reparte las tareas en bloques con hora y «sin hora»;
  `TimelineColumn` se comparte con la semana por horas del Calendario. Arrastrar usa el `id` de la tarea como `String`.
  La selección es `EventSelection` (id del bloque o del `AgendaItem` y su título, porque el id de una tarea es «nota:línea» y
  otra tarea puede ocupar esa línea si la nota cambia fuera); `resolve` da el `EventRef` y `EventPanel` pinta la ficha. El
  formulario es `TaskEditor` (con `TaskDraft`, puro), compartido con `TaskSheet`: guarda sobre la tarea con la que empezó
  (`origin`) y, si esa misma tarea se mueve mientras se edita, mezcla campo a campo (`TaskDraft.rebased`).
- Una fecha de formulario que empieza en hoy (`@State var date = Date()`) lleva `.followsToday($date)`: si no, con la app abierta
  de un día para otro, lo apuntado por la mañana iba al día anterior.
- Toda entrada de tareas en lenguaje natural (también `QuickCommand.task`) pasa por `Store.addTask(_ p: ParsedTask)`.
- Una función pura dentro de una vista (`static func` en un `View`) es `@MainActor`: llamada desde un test que no lo es, sus
  cierres abortan el proceso al comprobar el aislamiento (señal 5). Márcala `nonisolated` (ver `NotePeek.head`).
- Swift Testing: nada de `#require` dentro de otro `#require`; con funciones que lanzan, saca el valor a una variable antes del `#expect`.
- `sed -i` de macOS no es el de GNU: para editar varios archivos, Python.
- Registro: `Log.notes/icloud/backups/calendar/notifications` (`Log.swift`). Errores y cuentas `.public`; rutas `.private`;
  nunca el texto de una nota.
- «Charts: Custom UnitPoint values are not supported in AxisValueLabel's anchor property» sale en la consola con cualquier `Chart`
  (también uno sin ejes propios) en macOS 26, una vez por proceso: es de Charts, no de la app. No tocar los `anchor` por eso.
- EventKit y las notificaciones solo funcionan en el `.app` (necesitan el Info.plist de `build-app.sh`); con `swift test` no se puede
  probar contra Calendar real.

## Rendimiento (la ventaja frente a Obsidian: tiene que ir fluida)

- Medir siempre con el benchmark en release antes y después. Un pintado suelto con `ImageRenderer` es ruidoso: para comparar
  pantallas, el modo `VOT_BENCH_SCREEN` (pintados en 20 s) y `sample <pid> 9` para ver qué funciones pesan.
- Nada de expresiones regulares línea a línea sin un filtro previo por bytes (ver `Parse.tasks`, `NoteInfo.tags`, `Links.extract`).
- Lo que se pide en cada pintado y solo cambia con las notas se guarda: `alerts()` (`alertsCache`), `brokenLinkCount`,
  índices al leer la nota (`intakeIndex`, `paymentIndex`, `spentIndex`, `trendCache`). La barra lateral calcula sus indicadores en
  `.task(id: store.revision)`, no en cada fila.
- Fuera de Notas, una nota se pinta recortada (`NotePeek.head`, 250 líneas o 30 KB): `NoteBody` tarda ~0,5 ms por línea con formato.
- Listas largas: recortar con `ShowAllButton` (tablas de notas 40 filas, Peso 60…). Gráficas: `thinned(_:to:)` (120–400 puntos).
- `MDParser.inline` salta el analizador de Markdown si el texto no tiene ningún carácter con formato; no quitar ese atajo.
- **Qué repinta cada cambio** (lo mide `VOT_MATRIX=1 swift test --filter fluidezMatrix`; las comprobaciones de `FluidezTests` corren
  siempre). Reglas para no romperlo:
  - Las vistas leen notas con `store.read(rel)` (registra solo esa nota, `NoteSlot`), nunca `noteTexts`. Las tareas de una sola
    nota, con `store.tasks(in: rel)`, no `store.tasks.filter { $0.file == … }` (que registra todas las tareas). Una caché que se salta la
    lectura (como `budget`, `budgetYear` o `agenda`) tiene que registrar sus dependencias (`touch(rel)`, leer las propiedades) antes
    de devolver lo guardado.
  - `revision` no se observa: ninguna vista debe usarlo para refrescarse. Avisos y barra lateral están en `currentAlerts` y `sidebar`,
    publicados en `refreshPublished()` (aplazado con `refreshPublishedSoon()`); las copias, en `backupsStamp`; los enlaces, en `linksVersion`.
  - Las propiedades publicadas deben ser `Equatable` (la observación de Swift 6.3 no avisa si el valor no cambia); lo que cambia en
    cada edición y no se pinta (`undoStack`, `lastQuietWrite`…) va con `@ObservationIgnored`.
  - `ContentView` no debe leer nada que cambie en cada edición: el aviso de «guardado», el banner, el panel Hoy, las notas
    recientes y la cuenta atrás del enfoque son vistas aparte. El panel sí se repinta con las tareas (lo comprueba `FluidezTests`). Lo mismo
    con un `.task(id:)` que dependa de `textsVersion`: va en una vista invisible aparte (`MentionsWatcher` en Notas).
  - Lo que se recalcula con cada pulsación (el borrador del editor es estado de `NotasView`) se separa en vistas `Equatable`
    (`NoteListPanel`) que comparan solo lo que pintan.
- Mediciones guardadas para comparar: `.claude/mediciones/` (fuera de git).

## Forma de trabajar

- Una rama por tarea (`mejoras`, `novedades`…); `master` es la principal. Commits solo cuando se pidan, en español, separando código y documentación.
- Cada función nueva actualiza README y GUIA. Antes de dar algo por hecho: los tests de lo nuevo y de lo que toca (`swift test --filter`)
  y, si toca pantallas, una captura. `swift test` completo solo si el cambio toca algo compartido (Store, escaneo, agenda, repintados),
  si aparece un error o si el benchmark mide una ralentización.
