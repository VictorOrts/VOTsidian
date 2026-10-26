import AppIntents
import AppKit
import SwiftUI

@main
struct VOTsidianApp: App {
    @State private var store: Store
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("menuBar") private var menuBar = true
    @AppStorage(Pins.key) private var pinnedRaw = Pins.standard
    @AppStorage("todayPanel") private var panelOn = true

    init() {
        // Siri y Atajos usan el mismo `Store` que las ventanas (`Siri.swift`).
        let store = Store()
        _store = State(initialValue: store)
        AppDependencyManager.shared.add(dependency: store)
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
                .modifier(AppChrome(store: store, scheme: scheme))
                .frame(minWidth: 1000, minHeight: 640)
                .onAppear { NSApplication.shared.activate() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    // FSEvents ya avisa de los cambios: aquí basta una pasada en segundo plano, sin bloquear la ventana.
                    store.reloadInBackground()
                    store.startDailyBackup()
                    store.refreshSystemNotifications(force: true)
                    store.refreshCalendarSync()
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
            CommandGroup(after: .sidebar) {
                Button(panelOn ? "Ocultar el panel Hoy" : "Mostrar el panel Hoy") { panelOn.toggle() }.keyboardShortcut("0", modifiers: [.command, .option])
            }
            CommandMenu("Ir a") {
                Button("Atrás") { store.goBack() }.keyboardShortcut("[", modifiers: .command).disabled(!store.canGoBack)
                Button("Adelante") { store.goForward() }.keyboardShortcut("]", modifiers: .command).disabled(!store.canGoForward)
                Divider()
                // ⌘1 es Inicio y ⌘2…⌘9 las fijadas, en su orden: ocultar o enseñar un módulo no cambia los atajos.
                let pins = Pins.parse(pinnedRaw).filter(store.isVisible).prefix(8)
                Button("Inicio") { store.screen = .inicio }.keyboardShortcut("1", modifiers: .command)
                ForEach(Array(pins.enumerated()), id: \.offset) { i, s in
                    Button(s == .dia ? "Agenda" : store.title(s)) { store.go(s) }.keyboardShortcut(KeyEquivalent(Character(String(i + 2))), modifiers: .command)
                }
                Divider()
                ForEach(Screen.allCases.filter { $0 != .inicio && store.isVisible($0) && !pins.contains($0) }) { s in
                    Button(store.title(s)) { store.screen = s }
                }
            }
        }

        WindowGroup("Pantalla", id: "pantalla", for: Screen.self) { $screen in
            // Una ventana que macOS restaura puede ser de un módulo que ya se ocultó.
            let s = screen.flatMap { store.isVisible($0) ? $0 : nil } ?? .inicio
            ScreenView(screen: s)
                .navigationTitle(s == .dia ? "Agenda" : store.title(s))
                .modifier(AppChrome(store: store, scheme: scheme))
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 1000, height: 760)

        WindowGroup("Nota", id: "nota", for: String.self) { $path in
            ScrollView { NotePeek(path: path ?? "", inWindow: true).padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity) }
                .navigationTitle(((path ?? "") as NSString).deletingPathExtension.components(separatedBy: "/").last ?? "Nota")
                .modifier(AppChrome(store: store, scheme: scheme))
                .frame(minWidth: 420, minHeight: 400)
        }
        .defaultSize(width: 640, height: 720)

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

/// Lo que comparten todas las ventanas: los datos, el color, el tema y los enlaces entre notas.
private struct AppChrome: ViewModifier {
    let store: Store
    let scheme: ColorScheme?

    func body(content: Content) -> some View {
        content
            .environment(store)
            .environment(\.openURL, OpenURLAction { store.open(link: $0) })
            .textFieldStyle(.roundedBorder)
            .tint(Brand.accent)
            .preferredColorScheme(scheme)
    }
}
