import AppKit
import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Fluidez: qué se repinta con cada cambio
//
// Monta la ventana de verdad (NSHostingView), hace un cambio y cuenta qué cuerpos de pantalla se recalculan (`BodyCounter`).
// `VOT_MATRIX=1 swift test --filter fluidezMatrix` imprime la matriz completa; las comprobaciones de abajo corren siempre.

@MainActor private func settle(_ seconds: Double = 0.35) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

/// Ventana con la app en `screen`. Se devuelve para que siga viva mientras se mide.
@MainActor private func host(_ store: Store, _ screen: Screen) -> NSWindow {
    _ = NSApplication.shared
    // Las pestañas de Notas se recuerdan entre ejecuciones: sin limpiarlas, cada caso dependería del anterior.
    for key in ["openTabs", "activeTab", "recentNotes"] { UserDefaults.standard.removeObject(forKey: key) }
    store.screen = screen
    let view = NSHostingView(rootView: ContentView().environment(store).frame(width: 1280, height: 860))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    window.orderFrontRegardless()
    settle(0.6)
    return window
}

/// Carpeta sintética con una tarea que se puede marcar.
@MainActor private func makeStore() throws -> Store {
    let root = try syntheticVault()
    try "- [ ] previa 📅 \(isoDay(1))\n".write(to: root.appendingPathComponent("Notas/Previa.md"), atomically: true, encoding: .utf8)
    return Store(root: root)
}

private let edits: [(String, @MainActor (Store) -> Void)] = [
    ("peso", { $0.addWeight(date: DayKey.today(), kg: 70, note: "") }),
    ("nota normal", { $0.edit("Notas/B.md") { $0 + "\nmás" } }),
    ("gasto", { $0.addExpense(9, category: "Alimentación", note: "pan", date: DayKey.today()) }),
    ("tarea", { s in if let t = s.tasks.first(where: { $0.text == "previa" }) { s.setTask(t, done: true) } }),
    ("vehículo", { $0.addRepostaje(date: DayKey.today(), km: 115_500, liters: 30, amount: 45, expense: false) }),
    ("escribir 10 veces", { s in for i in 0..<10 { s.edit("Notas/B.md") { $0 + "\n\(i)" }; settle(0.02) } }),
]

/// La ventana tal como se ve ahora, para saber si un cambio llegó a la pantalla.
@MainActor private func snapshot(_ window: NSWindow) -> Data? {
    guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep.tiffRepresentation
}

/// Cuerpos recalculados por `edit` estando en `screen`, y si la ventana se ve distinta después (sin el aviso de «guardado»).
@MainActor private func repaints(_ screen: Screen, _ edit: @MainActor (Store) -> Void) throws -> (counts: [String: Int], visible: Bool) {
    let store = try makeStore()
    let window = host(store, screen)
    defer { window.orderOut(nil) }
    let before = snapshot(window)
    BodyCounter.reset()
    edit(store)
    settle()
    let counts = BodyCounter.counts
    store.lastChange = nil
    settle(0.6)
    return (counts, snapshot(window) != before)
}

@MainActor @Test func fluidezMatrix() throws {
    guard ProcessInfo.processInfo.environment["VOT_MATRIX"] != nil else { return }
    let screens: [Screen] = [.inicio, .calendario, .vehiculo, .gastos, .notas, .peso, .tareas, .avisos, .viajes]
    var total = 0
    for (name, edit) in edits {
        for screen in screens {
            let (c, visible) = try repaints(screen, edit)
            total += c.values.reduce(0, +)
            print("MATRIZ \(name) | en \(screen) | \(c.values.reduce(0, +)) | \(visible ? "se ve distinto" : "igual") | " + c.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " "))
        }
    }
    print("MATRIZ total de cuerpos recalculados: \(total)")
}

// MARK: Lo que debe repintarse se repinta, y lo ajeno no

/// Inicio con una sola tarjeta visible, para que un cambio en la imagen solo pueda venir de ella.
@MainActor private func inicioOnly(_ card: HomeCard, _ edit: @MainActor (Store) -> Void) throws -> Bool {
    UserDefaults.standard.set(HomeCard.allCases.map { "\($0.rawValue):\($0 == card ? 1 : 0)" }.joined(separator: ","), forKey: "inicioLayout")
    defer { UserDefaults.standard.removeObject(forKey: "inicioLayout") }
    return try repaints(.inicio, edit).visible
}

@MainActor @Test func screensFollowTheirOwnDataOnly() throws {
    // las tarjetas de Inicio se actualizan con sus datos…
    #expect(try inicioOnly(.gastos) { $0.addExpense(25, category: "Alimentación", note: "x", date: DayKey.today()) }, "la tarjeta de Gastos no se actualizó")
    #expect(try inicioOnly(.vehiculo) { $0.addRepostaje(date: DayKey.today(), km: 116_000, liters: 30, amount: 45, expense: false) }, "la tarjeta de Vehículo no se actualizó")
    #expect(try inicioOnly(.peso) { $0.addWeight(date: DayKey.today(), kg: 65, note: "") }, "la tarjeta de Peso no se actualizó")
    // …y no con lo que no les toca
    #expect(try !inicioOnly(.gastos) { $0.edit("Notas/B.md") { $0 + "\nmás" } }, "la tarjeta de Gastos se repintó con una nota ajena")
    // la pantalla de un módulo, igual
    let own = try repaints(.vehiculo) { $0.addRepostaje(date: DayKey.today(), km: 116_000, liters: 30, amount: 45, expense: false) }
    #expect(own.visible && own.counts["VehiculoView"] != nil)
    let other = try repaints(.vehiculo) { $0.edit("Notas/B.md") { $0 + "\nmás" } }
    #expect(!other.visible && other.counts.isEmpty, "Vehículo se repintó con una nota ajena: \(other.counts)")
}

@MainActor @Test func typingInTheEditorDoesNotRecomputeTheNoteList() throws {
    let store = try makeStore()
    setenv("VOT_EDIT", "1", 1)
    defer { unsetenv("VOT_EDIT") }
    store.pendingNote = "Notas/B.md"
    let window = host(store, .notas)
    defer { window.orderOut(nil) }
    func textViews(_ v: NSView) -> [NSTextView] { (v as? NSTextView).map { [$0] } ?? v.subviews.flatMap(textViews) }
    let content = try #require(window.contentView)
    let editor = try #require(textViews(content).max { $0.string.count < $1.string.count })
    window.makeFirstResponder(editor)
    BodyCounter.reset()
    for _ in 0..<20 { editor.insertText("a", replacementRange: editor.selectedRange()); settle(0.01) }
    settle()
    #expect(BodyCounter.counts["NotasView"] ?? 0 > 0)
    #expect(BodyCounter.counts["NoteListPanel"] == nil, "la lista de notas se recalculó al escribir: \(BodyCounter.counts)")
    #expect(BodyCounter.counts["ContentView"] == nil, "la ventana entera se recalculó al escribir: \(BodyCounter.counts)")
}

@MainActor @Test func theNoteListFollowsNewNotes() throws {
    let created = try repaints(.notas) { _ = $0.createNote(folder: "Casa", name: "Recién creada", template: "En blanco") }
    #expect(created.visible && created.counts["NoteListPanel"] != nil, "la lista no enseñó la nota nueva: \(created.counts)")
}

@MainActor @Test func publishedAlertsAndSidebarFollowChanges() throws {
    let store = try makeStore()
    let before = store.currentAlerts
    store.addExpense(9, category: "Alimentación", note: "pan", date: DayKey.today())
    settle(0.05)   // se publican en la siguiente vuelta del bucle principal
    #expect(store.currentAlerts != before && store.currentAlerts == store.alerts(), "los avisos publicados no se pusieron al día")
    let tasks = store.sidebar.counts[.tareas]
    store.addTask("nueva para hoy", due: DayKey.today())
    settle(0.05)
    #expect(store.sidebar.counts[.tareas] != tasks && store.sidebar == SidebarState(counts: store.sidebarCounts(), medicationDays: store.medicacion.daysUntilNext,
                                                                                  tasksOverdue: store.sidebar.tasksOverdue))
    store.hiddenModules.insert(.finanzas)   // ocultar un módulo publica al momento
    #expect(!store.currentAlerts.contains { $0.screen == .gastos || $0.screen == .finanzas })
}

@Test func thinnedWeightChartsKeepSpikes() throws {
    let start = try #require(DayKey.date("2024-01-01"))
    var records = (0..<1100).map { WeightRecord(date: DayKey.adding(days: $0, to: start), kg: 90 - Double($0) / 100, note: "", line: $0) }
    records[537].kg = 120   // un día raro
    records[811].kg = 60
    let thin = thinnedKeepingExtremes(records, to: 120)
    #expect(thin.count <= 120 && thin.first == records.first && thin.last == records.last)
    #expect(thin.contains { $0.kg == 120 } && thin.contains { $0.kg == 60 }, "se perdió un pico al recortar la gráfica")
    #expect(zip(thin, thin.dropFirst()).allSatisfy { $0.date < $1.date })   // en orden y sin repetir
    #expect(thinnedKeepingExtremes(Array(records.prefix(50)), to: 120).count == 50)
}
