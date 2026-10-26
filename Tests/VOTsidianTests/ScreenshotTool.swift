import AppKit
import SwiftUI
import Testing
@testable import VOTsidian

// Capturas de todas las pantallas, en claro y oscuro, para revisar el diseño. Solo corre con
// `VOT_SHOTS=/carpeta/salida VAULT_COPY=/ruta/vault swift test --filter screenshots`; trabaja sobre una copia temporal.
// `VOT_SHOT_WIDTH` cambia el ancho de la ventana (1280 por defecto; 1110 deja la pantalla en 600 con el panel Hoy).
@MainActor @Test func screenshots() throws {
    guard let out = ProcessInfo.processInfo.environment["VOT_SHOTS"] else { return }
    let outDir = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let store = Store(root: try ProcessInfo.processInfo.environment["VAULT_COPY"].map(tempVaultCopy) ?? syntheticVault())
    _ = NSApplication.shared
    for scheme in [ColorScheme.light, .dark] {
        for screen in Screen.allCases {
            if let only = ProcessInfo.processInfo.environment["VOT_SHOT_SCREEN"], String(describing: screen) != only { continue }
            store.screen = screen
            let host = NSHostingView(rootView: ContentView().environment(store).tint(Brand.accent)
                .textFieldStyle(.roundedBorder).environment(\.colorScheme, scheme).preferredColorScheme(scheme))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Double(ProcessInfo.processInfo.environment["VOT_SHOT_WIDTH"] ?? "") ?? 1280, height: Double(ProcessInfo.processInfo.environment["VOT_SHOT_HEIGHT"] ?? "") ?? 860), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = host
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(1.2))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            let name = "\(scheme == .dark ? "oscuro" : "claro")-\(String(describing: screen)).png"
            try rep.representation(using: .png, properties: [:])?.write(to: outDir.appendingPathComponent(name))
            window.orderOut(nil)
        }
    }
}
