import AppKit
import SwiftUI

@main
struct VOTsidianApp: App {
    @State private var store = Store()
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("menuBar") private var menuBar = true

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        // Se recibe en el hilo principal y antes de salir: guarda lo que el autoguardado aún no había guardado.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { PendingSaves.flush() }
        }
    }

    private var scheme: ColorScheme? {
        let raw = ProcessInfo.processInfo.environment["VOT_APPEARANCE"] ?? appearance
        return Appearance(rawValue: raw)?.scheme
    }

    var body: some Scene {
        Window("VOTsidian", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 1000, minHeight: 640)
                .textFieldStyle(.roundedBorder)
                .tint(Brand.accent)
                .preferredColorScheme(scheme)
                .onAppear { NSApplication.shared.activate() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    // FSEvents ya avisa de los cambios: aquí basta una pasada en segundo plano, sin bloquear la ventana.
                    store.reloadInBackground()
                    store.startDailyBackup()
                    store.refreshSystemNotifications(force: true)
                }
        }
        .defaultSize(width: 1280, height: 860)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Captura rápida…") { store.showQuickAdd = true }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Buscar…") { store.showPalette = true }.keyboardShortcut("k")
            }
            CommandGroup(after: .undoRedo) {
                Button("Deshacer último cambio de la app") { store.undo() }.keyboardShortcut("z", modifiers: [.command, .option]).disabled(!store.canUndo)
            }
            CommandMenu("Ir a") {
                ForEach(Array(Screen.allCases.filter(store.isVisible).enumerated()), id: \.offset) { i, s in
                    if i < 9 { Button(store.title(s)) { store.screen = s }.keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command) }
                    else { Button(store.title(s)) { store.screen = s } }
                }
            }
        }

        MenuBarExtra(isInserted: $menuBar) {
            MenuBarPanel().environment(store).tint(Brand.accent).textFieldStyle(.roundedBorder)
        } label: {
            // Con el módulo de peso, la báscula y el último peso; si no, solo el icono de la app en la barra.
            if store.isVisible(.peso), let kg = store.weight.last?.kg {
                HStack(spacing: 4) { Image(systemName: "scalemass"); Text(fmt(kg)) }
            } else {
                Image(systemName: "checklist")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
