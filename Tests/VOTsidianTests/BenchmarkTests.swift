import AppKit
import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Benchmark: una carpeta como la de alguien que lleva 3 años usando la app
//
// No corre en la suite normal: `VOT_BENCH=1 swift test -c release --filter heavyUserBenchmark` imprime cuánto tarda cargar,
// recargar, editar, calcular avisos y pintar cada pantalla con 2.200 notas, miles de filas de peso y tomas, 36 meses de
// gastos y los módulos llenos. Sirve para comparar antes y después de un cambio.
@MainActor @Test func heavyUserBenchmark() throws {
    guard ProcessInfo.processInfo.environment["VOT_BENCH"] != nil else { return }
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString)")
    let v = tmp.appendingPathComponent("V")
    func w(_ rel: String, _ text: String) throws {
        let u = v.appendingPathComponent(rel)
        try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: u, atomically: true, encoding: .utf8)
    }
    let today = DayKey.today()
    let days = (0..<1100).map { DayKey.adding(days: -$0, to: today) }.reversed()
    try w(VaultPath.peso, "---\nobjetivo_peso_kg: 80\n---\n| Fecha | Peso (kg) | Notas |\n| :-- | :-: | :-- |\n" + days.enumerated().map { "| \(DayKey.dmy($1)) | \(110 - Double($0) / 40) | |" }.joined(separator: "\n") + "\n")
    try w(VaultPath.medicacion, "## Medicamentos\n\n| Medicamento | Dosis | Forma | Cada | Horas |\n| - | - | - | - | - |\n| A | 1 mg | Pastilla | 1 | 09:00, 21:00 |\n| B | 0,5 mg | Inyección | 7 | |\n| C | 400 mg | Pastilla | Si hace falta | |\n\n## Registro\n\n| Fecha | Medicamento | Dosis | Zona | Notas |\n| - | - | - | - | - |\n"
          + days.suffix(730).flatMap { d in ["| \(DayKey.string(d)) | A | 1 mg | | |", "| \(DayKey.string(d)) | A | 1 mg | | |"] }.joined(separator: "\n") + "\n")
    for m in 0..<36 { let d = DayKey.calendar().date(byAdding: .month, value: -m, to: today)!; try w("Finanzas/Gastos/\(Budget.monthKey(d)).md", gastosFixture(d, full: m > 0)) }
    for k in 0..<156 { let d = DayKey.adding(days: -7 * k, to: today); try w("\(VaultPath.revisiones)/\(DayKey.weekKey(d)).md", weekFixture) }
    for d in days.suffix(1000) { try w("Diario/\(DayKey.string(d)).md", "---\nanimo: \(Int.random(in: 1...5))\nsueno_h: 7\n---\n# Día\n\n- algo que pasó\n") }
    for f in 0..<20 { for n in 0..<50 { try w("Carpeta \(f)/Nota \(f)-\(n).md", "---\ntipo: nota\n---\n# Nota\n" + String(repeating: "lorem ipsum dolor ", count: 80) + "\n- [ ] Tarea \(f)-\(n) 📅 \(DayKey.string(DayKey.adding(days: n, to: today)))\n[[Nota \(f)-\((n + 1) % 50)]]\n") } }
    try w(VaultPath.vehiculo, vehiculoFixture + "\n" + (0..<300).map { "| \(DayKey.string(DayKey.adding(days: -3 * $0, to: today))) | \(114_000 - 300 * $0) | 40 | 60 € |" }.joined(separator: "\n"))
    try w(VaultPath.suscripciones, "## Servicios\n\n| Servicio | Importe | Cada | Próximo cobro | Partida | Estado |\n| - | - | - | - | - | - |\n" + (0..<30).map { "| S\($0) | 9,99 € | Mensual | 2025-0\($0 % 9 + 1)-1\($0 % 9) | | Activa |" }.joined(separator: "\n"))
    try w(VaultPath.prestamos, prestamosFixture + (0..<100).map { "| \(DayKey.string(DayKey.adding(days: -30 * $0, to: today))) | Coche | 50 | |" }.joined(separator: "\n"))
    try w(VaultPath.lecturas, "---\nobjetivo_anual: 20\n---\n## Libros\n\n| Título | Autor | Estado | Empezado | Terminado | Nota | Páginas |\n| - | - | - | - | - | - | - |\n" + (0..<300).map { "| Libro \($0) | A | Terminado | \(DayKey.string(DayKey.adding(days: -3 * $0 - 10, to: today))) | \(DayKey.string(DayKey.adding(days: -3 * $0, to: today))) | 4 | 300 |" }.joined(separator: "\n"))
    try w(VaultPath.viajes, "## Destinos\n\n| Destino | Salida | Vuelta | Presupuesto | Estado |\n| - | - | - | - | - |\n" + (0..<40).map { "| V\($0) | \(DayKey.string(DayKey.adding(days: 30 * $0 - 600, to: today))) | \(DayKey.string(DayKey.adding(days: 30 * $0 - 595, to: today))) | 800 | Reservado |" }.joined(separator: "\n")
          + "\n\n## Gastos del viaje\n\n| Fecha | Viaje | Concepto | Importe |\n| - | - | - | - |\n" + (0..<400).map { "| \(DayKey.string(today)) | V\($0 % 40) | c | 10 |" }.joined(separator: "\n"))
    try w(VaultPath.personas, "| Persona | Relación | Cumpleaños | Última vez |\n| - | - | - | - |\n" + (0..<200).map { "| P\($0) | amigo | 1990-\(String(format: "%02d", $0 % 12 + 1))-\(String(format: "%02d", $0 % 28 + 1)) | 2026-01-01 |" }.joined(separator: "\n"))

    let clock = ContinuousClock()
    func t(_ name: String, _ body: () -> Void) { print("BENCH \(name): \(clock.measure(body))") }
    var made: Store?
    t("carga en frío") { made = Store(root: v, backups: tmp.appendingPathComponent("C")) }
    let store = made!
    print("BENCH notas \(store.notes.count) tareas \(store.tasks.count)")
    t("recarga completa") { store.reload() }
    t("recarga de 1 nota") { store.reload(changed: [VaultPath.peso]) }
    t("edición de peso") { store.addWeight(date: today, kg: 80, note: "") }
    t("edición siguiente") { store.addWeight(date: DayKey.adding(days: -1, to: today), kg: 80, note: "") }
    let pesoText = store.read(VaultPath.peso), medText = store.read(VaultPath.medicacion)
    t("Parse.weight (1100 filas)") { _ = Parse.weight(pesoText) }
    t("Parse.medicacion (1460 filas)") { _ = Parse.medicacion(medText) }
    t("makeEntry peso") { _ = Store.makeEntry(text: pesoText, rel: VaultPath.peso, mtime: Date(), size: 0) }
    t("makeEntry medicación") { _ = Store.makeEntry(text: medText, rel: VaultPath.medicacion, mtime: Date(), size: 0) }
    t("Parse.tasks peso") { _ = Parse.tasks(pesoText, file: "x") }
    t("NoteInfo.tags peso") { _ = NoteInfo.tags(pesoText) }
    t("NoteInfo.snippet peso") { _ = NoteInfo.snippet(pesoText) }
    t("NoteInfo.aliases peso") { _ = NoteInfo.aliases(pesoText) }
    t("Links.extract peso") { _ = Links.extract(pesoText) }
    t("MD.frontmatter peso") { _ = MD.frontmatter(pesoText) }
    t("MD.fenced peso") { _ = MD.fenced(MD.lines(pesoText)) }
    t("buildLinks") { store.buildLinks(links: store.fileCache.mapValues { $0.parsed.links }) }
    t("ordenar notas") { _ = store.notes.sorted { ($0.folder, $0.name) < ($1.folder, $1.name) } }
    t("DayKey.dmyDate x1100") { for _ in 0..<1100 { _ = DayKey.dmyDate("23/10/2026") } }
    t("MD.number x1100") { for _ in 0..<1100 { _ = MD.number("105,5") } }
    t("MD.tableRows peso") { _ = MD.tableRows(MD.lines(pesoText)) }
    t("recarga de medicación") { store.reload(changed: [VaultPath.medicacion]) }
    t("recarga de una nota normal") { store.reload(changed: ["Carpeta 0/Nota 0-0.md"]) }
    t("alerts()") { _ = store.alerts() }
    t("· budgetAlerts") { _ = store.budgetAlerts() }
    t("· upcomingPayments") { _ = store.upcomingPayments() }
    t("· conflictCopies") { _ = store.conflictCopies }
    t("· daysSinceLastBackup") { _ = store.daysSinceLastBackup() }
    t("· budgetMonths") { _ = store.budgetMonths }
    t("· medicación") { _ = (store.medicacion.active(on: today), store.medicacion.pending(today: today)) }
    t("· módulos") { _ = (store.vehiculoAlerts(), store.suscripcionAlerts(), store.prestamoAlerts(), store.viajeAlerts(), store.tramiteAlerts()) }
    t("· revisión mensual") { _ = store.monthReview(Budget.monthKey(today)) }
    t("refreshPublished") { store.refreshPublished() }
    t("alerts() x10") { for _ in 0..<10 { _ = store.alerts() } }
    t("sidebarCounts()") { _ = store.sidebarCounts() }
    t("agenda mes frío") { _ = store.agenda(from: today, to: DayKey.adding(days: 42, to: today)) }
    t("reminderSources+ICS") { _ = ICS.events(store.reminderSources(), plan: store.reminderPlan()) }
    t("ICS→EventKit specs") { _ = ICS.events(store.reminderSources(), plan: store.reminderPlan()).map(CalendarEventSpec.init) }
    t("budgetYear") { _ = store.budgetYear(DayKey.calendar().component(.year, from: today)) }
    t("búsqueda ⌘K (todas las notas)") { let q = SearchQuery.parse("lorem tarea"); _ = store.notes.filter { SearchEngine.matches(MD.fold(store.read($0.path)), q) } }
    t("brokenLinks") { _ = store.brokenLinks() }
    t("exportar CSV") { _ = try? store.exportData(to: tmp.appendingPathComponent("E")) }
    func paint<V: View>(_ name: String, _ view: V) {
        t("pintar \(name)") { let r = ImageRenderer(content: view.environment(store).frame(width: 1100, height: 900)); r.scale = 1; _ = r.cgImage }
    }
    // `VOT_BENCH_TYPING=1`: escribe 200 letras en una nota abierta en el editor y mide cuánto tarda cada una en llegar a la pantalla.
    if ProcessInfo.processInfo.environment["VOT_BENCH_TYPING"] != nil {
        setenv("VOT_EDIT", "1", 1)
        _ = NSApplication.shared
        store.pendingNote = "Carpeta 3/Nota 3-7.md"
        store.screen = .notas
        let view = NSHostingView(rootView: ContentView().environment(store).frame(width: 1280, height: 860))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        func textViews(_ v: NSView) -> [NSTextView] { (v as? NSTextView).map { [$0] } ?? v.subviews.flatMap(textViews) }
        guard let editor = textViews(view).max(by: { $0.string.count < $1.string.count }) else { print("BENCH sin editor"); return }
        window.makeFirstResponder(editor)
        BodyCounter.reset()
        let start = ContinuousClock.now
        for _ in 0..<200 {
            editor.insertText("a", replacementRange: editor.selectedRange())
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
        }
        let elapsed = ContinuousClock.now - start
        print("BENCH escribir 200 letras: \(elapsed) (\(elapsed / 200) por letra); cuerpos: \(BodyCounter.counts.sorted { $0.key < $1.key })")
        unsetenv("VOT_EDIT")
        return
    }
    // `VOT_BENCH_SCREEN=viajes`: pinta esa pantalla una y otra vez durante 20 s, para perfilarla con `sample`.
    if let only = ProcessInfo.processInfo.environment["VOT_BENCH_SCREEN"], let screen = Screen.allCases.first(where: { String(describing: $0) == only }) {
        store.screen = screen
        let end = Date().addingTimeInterval(20)
        var n = 0
        while Date() < end { let r = ImageRenderer(content: ContentView().environment(store).frame(width: 1280, height: 900)); r.scale = 1; _ = r.cgImage; n += 1 }
        print("BENCH \(only): \(n) pintados en 20 s")
        return
    }
    paint("Inicio", InicioView(go: { _ in })); paint("Inicio otra vez", InicioView(go: { _ in }))
    for c in HomeCard.allCases {
        UserDefaults.standard.set(HomeCard.allCases.map { "\($0.rawValue):\($0 == c ? 1 : 0)" }.joined(separator: ","), forKey: "inicioLayout")
        paint("Inicio solo \(c.rawValue)", InicioView(go: { _ in }))
    }
    UserDefaults.standard.set(HomeCard.allCases.map { "\($0.rawValue):0" }.joined(separator: ","), forKey: "inicioLayout")
    paint("Inicio sin tarjetas", InicioView(go: { _ in }))
    UserDefaults.standard.removeObject(forKey: "inicioLayout")
    paint("Avisos", RemindersView()); paint("Calendario", CalendarioView()); paint("Peso", PesoView()); paint("Correlaciones", CorrelacionesView())
    paint("Medicación", MedicacionView()); paint("Gastos", GastosView()); paint("Finanzas", FinanzasView()); paint("Semana", SemanaView()); paint("Mes", MesView())
    paint("Vehículo", VehiculoView()); paint("Suscripciones", SuscripcionesView()); paint("Préstamos", PrestamosView()); paint("Lecturas", LecturasView()); paint("Viajes", ViajesView())
    paint("Notas", NotasView()); paint("Bases", BasesView()); paint("Grafo", GrafoView()); paint("Personas", PersonasView()); paint("Tareas", TareasView()); paint("Planificar", PlanificarView())
    paint("Palette", CommandPalette()); paint("MenuBar", MenuBarPanel())
}
