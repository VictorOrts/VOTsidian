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
