import AppKit
import SwiftUI
import Testing
@testable import VOTsidian

// Desde macOS 27 cada pestaña de un control segmentado mide lo que la más larga: con un ancho fijo o un hueco estrecho el
// control se corta por dentro (Tareas, «Vencidas (12)») o empuja la vista y la saca de la ventana (la captura rápida).
// Aquí se pinta cada pantalla en una ventana de verdad y se mira cada `NSSegmentedControl`.

/// Los controles segmentados que se cortan (más estrechos que su ancho natural o fuera de la ventana) y cuántos hay.
@MainActor private func clippedSegments<V: View>(_ view: V, width: CGFloat, height: CGFloat = 860) -> (problems: [String], seen: Int) {
    let host = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .fullSizeContentView],
                          backing: .buffered, defer: false)
    window.contentView = host
    window.orderFrontRegardless()
    defer { window.orderOut(nil) }
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))

    var problems: [String] = []
    var seen = 0
    func walk(_ v: NSView) {
        if let s = v as? NSSegmentedControl, !s.isHiddenOrHasHiddenAncestor, s.segmentCount > 0 {
            seen += 1
            let labels = (0..<s.segmentCount).map { s.label(forSegment: $0) ?? "?" }.joined(separator: "|")
            let frame = s.convert(s.bounds, to: nil)
            let natural = s.intrinsicContentSize.width
            if frame.width + 1 < natural { problems.append("«\(labels)» mide \(Int(frame.width)) de \(Int(natural))") }
            if frame.minX < -1 || frame.maxX > width + 1 { problems.append("«\(labels)» se sale de la ventana (x \(Int(frame.minX))…\(Int(frame.maxX)))") }
        }
        v.subviews.forEach(walk)
    }
    walk(host)
    return (problems, seen)
}

/// El detector caza los dos fallos: un control con ancho fijo más estrecho que sus pestañas, y uno que no cabe en la ventana.
@Test @MainActor func segmentedDetectorCatchesClipping() {
    _ = NSApplication.shared
    let labels = ["Cualquier cosa", "Tarea", "Gasto", "Peso", "Toma", "Idea"]
    func picker() -> some View {
        Picker("", selection: .constant(labels[0])) { ForEach(labels, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).labelsHidden()
    }
    #expect(clippedSegments(picker().frame(width: 300), width: 600).problems.contains { $0.contains("mide") })
    #expect(clippedSegments(VStack { picker() }.frame(width: 300), width: 300).problems.contains { $0.contains("se sale") })
    let fits = clippedSegments(picker().fixedSize(), width: 900)
    #expect(fits.seen == 1 && fits.problems.isEmpty)
}

/// Todas las pantallas al ancho más estrecho que pueden tener: con el panel Hoy, que sale cuando el detalle mide 900 pt o más
/// y se queda 300, la pantalla mide 600. Sin el panel, nunca menos de 790 (ventana de 1000 menos la barra lateral).
@Test @MainActor func segmentedControlsFitEveryScreen() throws {
    let store = Store(root: try syntheticVault())
    _ = NSApplication.shared
    var total = 0
    for screen in Screen.allCases {
        let r = clippedSegments(ScreenView(screen: screen).environment(store).tint(Brand.accent).textFieldStyle(.roundedBorder), width: 600)
        total += r.seen
        #expect(r.problems.isEmpty, "\(screen.rawValue) a 600 pt: \(r.problems.joined(separator: "; "))")
    }
    #expect(total >= 9, "solo \(total) controles")   // si no encuentra controles, el test no prueba nada
    store.peekNote = store.notes.first?.path   // con una nota abierta al lado sale «Hoy | Nota»
    let panel = clippedSegments(HoyPanel().environment(store).frame(width: 300), width: 300)
    #expect(panel.seen == 1 && panel.problems.isEmpty, "Panel Hoy (\(panel.seen)): \(panel.problems.joined(separator: "; "))")
}

@Test @MainActor func segmentedControlsFitSheetsAndPanel() throws {
    let store = Store(root: try syntheticVault())
    _ = NSApplication.shared
    let quick = clippedSegments(QuickAddSheet().environment(store).fixedSize(), width: QuickAddSheet.width + 40, height: 400)
    #expect(quick.seen == 1 && quick.problems.isEmpty, "Captura rápida: \(quick.problems.joined(separator: "; "))")
    store.addTask("Llamar al taller", due: DayKey.today())
    let task = try #require(store.tasks.first { !$0.done })
    // El editor de tareas sale en el panel de Mi día y el Calendario (300 pt: la prioridad pasa a menú) y en su hoja (480 pt).
    for width in [300.0, 480.0] {
        let r = clippedSegments(TaskEditor(task: task) {}.environment(store).padding(12).frame(width: width), width: width, height: 700)
        #expect(r.seen == (width > 400 ? 1 : 0) && r.problems.isEmpty, "Editor de tareas a \(Int(width)) pt (\(r.seen)): \(r.problems.joined(separator: "; "))")
    }
}
