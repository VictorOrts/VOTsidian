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

/// Cuerpos recalculados por `edit` estando en `screen`.
@MainActor private func repaints(_ screen: Screen, _ edit: @MainActor (Store) -> Void) throws -> [String: Int] {
    let store = try makeStore()
    let window = host(store, screen)
    defer { window.orderOut(nil) }
    BodyCounter.reset()
    edit(store)
    settle()
    return BodyCounter.counts
}

@MainActor @Test func fluidezMatrix() throws {
    guard ProcessInfo.processInfo.environment["VOT_MATRIX"] != nil else { return }
    let screens: [Screen] = [.inicio, .calendario, .vehiculo, .gastos, .notas, .peso, .tareas, .avisos, .viajes]
    var total = 0
    for (name, edit) in edits {
        for screen in screens {
            let c = try repaints(screen, edit)
            total += c.values.reduce(0, +)
            print("MATRIZ \(name) | en \(screen) | \(c.values.reduce(0, +)) | " + c.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " "))
        }
    }
    print("MATRIZ total de cuerpos recalculados: \(total)")
}
