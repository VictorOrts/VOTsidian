# VOTsidian: notas para trabajar en el código

Agenda personal para macOS 26 en SwiftUI (paquete Swift 6.3, sin dependencias). Todo se guarda en notas Markdown de una carpeta
del usuario, compatible con Obsidian: **las notas son la fuente de verdad**, no hay base de datos. Interfaz, comentarios,
mensajes de commit y documentación, en español. Formato de cada nota para el usuario: [GUIA.md](GUIA.md).

## Comandos

```bash
swift build                                    # compilar
swift test                                     # ~220 tests, ~35 s (incluye fuzz)
./scripts/build-app.sh                         # build/VOTsidian.app (release, firmada)
VOT_SHOTS=.claude/capturas VOT_SHOT_SCREEN=vehiculo VOT_SHOT_HEIGHT=1500 swift test --filter screenshots   # captura de una pantalla
VOT_FUZZ=10 VOT_FUZZ_SEED=3 swift test --filter FuzzTests                                               # fuzz a fondo
VOT_BENCH=1 swift test -c release --filter heavyUserBenchmark                                            # tiempos con 3 años de datos
SWIFT_BACKTRACE=enable=yes,color=no,interactive=no,symbolicate=full swift test --filter X                # traza si un test cierra el proceso
```

- `VOT_SCREEN=vehiculo` abre la app en esa pantalla. `VAULT_COPY=/ruta` hace que los tests de humo usen una copia de notas reales.
- Capturas de referencia de todas las pantallas (vault sintético, modo claro): `.claude/capturas/` (fuera de git).
  El modo oscuro sale con el texto invisible en la herramienta de capturas: es una limitación suya, también en `master`.

## Arquitectura

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
- Módulos ocultos: `hiddenModules`; los nuevos se ocultan solos en carpetas ya configuradas (`registerNewModules`, `knownModules`).

## Añadir un módulo (todos los puntos)

1. `Sources/VOTsidian/X.swift`: modelo `XData`, `Parse.x`, `Edit.addX…` (con `Edit.addRow(text, section:)`), acciones en `extension Store`,
   y `xAlerts(today:)` si avisa. `XView.swift`: la pantalla (`MissingNoteBanner`, `Tile`, `Card`, `AlertList(alerts:emptyText:)`, `NoteTables`).
2. `Store.swift`: `VaultPath.defaults` + `static var x`, comentario de claves, `private(set) var x = XData()`, `derive(VaultPath.x)`.
3. `ContentView.swift`: `Screen` (case + icono + sección de la barra lateral + vista en `detail`).
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
- Números de notas: `MD.number` (cifras ASCII) y `MD.int` (nunca `Int(Double)`: un número enorme cierra la app). Insertar líneas
  con `insertClamped`. Plegar texto conservando posiciones con `NaturalDate.aligned`. Fechas con `[0-9]`, no `\d`.
- Las notas con `tipo: compra` o `tipo: viajes` no aportan tareas (`Store.notTaskTypes`).
- Swift Testing: nada de `#require` dentro de otro `#require`; con funciones que lanzan, saca el valor a una variable antes del `#expect`.
- `sed -i` de macOS no es el de GNU: para editar varios archivos, Python.
- EventKit y las notificaciones solo funcionan en el `.app` (necesitan el Info.plist de `build-app.sh`); con `swift test` no se puede
  probar contra Calendar real.

## Forma de trabajar

- Rama de trabajo `novedades`; `master` es la principal. Commits solo cuando se pidan, en español, separando código y documentación.
- Cada función nueva actualiza README y GUIA. Antes de dar algo por hecho: `swift test` completo y, si toca pantallas, una captura.
