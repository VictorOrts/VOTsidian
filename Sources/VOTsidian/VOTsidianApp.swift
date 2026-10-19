import AppKit
import SwiftUI

@main
struct VOTsidianApp: App {
    @State private var store = Store()
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("menuBar") private var menuBar = true
    @AppStorage("systemNotifications") private var systemNotifications = false

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
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
                    store.reload()
                    if systemNotifications {
                        let events = ICS.events(store.reminderSources(), plan: ReminderPlan.stored)
                        Task { _ = await Notifier.schedule(events) }
                    }
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
                ForEach(Array(Screen.allCases.enumerated()), id: \.offset) { i, s in
                    if i < 9 { Button(s.rawValue) { store.screen = s }.keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command) }
                    else { Button(s.rawValue) { store.screen = s } }
                }
            }
        }

        MenuBarExtra(isInserted: $menuBar) {
            MenuBarPanel().environment(store).tint(Brand.accent).textFieldStyle(.roundedBorder)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "scalemass")
                Text(store.weight.last.map { String(format: "%.1f", $0.kg) } ?? "")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
