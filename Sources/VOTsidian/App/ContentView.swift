import SwiftUI

enum Screen: String, CaseIterable, Identifiable, Codable {
    case inicio = "Inicio", dia = "Mi día", tareas = "Tareas", calendario = "Calendario", planificar = "Planificar semana", semana = "Revisión semanal", mes = "Revisión mensual", proyectos = "Proyectos", objetivos = "Objetivos"
    case peso = "Peso", nutricion = "Plan nutricional", medicacion = "Medicación", salud = "Salud y médicos", correlaciones = "Correlaciones"
    case casa = "Casa", compra = "Compra", moda = "Moda", mascota = "Mascota", vehiculo = "Vehículo", personas = "Personas", documentos = "Documentos", finanzas = "Finanzas", gastos = "Gastos"
    case suscripciones = "Suscripciones", prestamos = "Préstamos", lecturas = "Lecturas", viajes = "Viajes", tramites = "Trámites y seguros"
    case notas = "Notas", bases = "Bases", grafo = "Grafo", lienzo = "Lienzo", enlaces = "Enlaces rotos", avisos = "Avisos", ajustes = "Ajustes"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .inicio: "house"
        case .dia: "sun.max"
        case .tareas: "checklist"
        case .calendario: "calendar"
        case .planificar: "rectangle.grid.3x2"
        case .semana: "calendar.badge.checkmark"
        case .mes: "calendar.badge.clock"
        case .proyectos: "folder"
        case .objetivos: "target"
        case .peso: "scalemass"
        case .nutricion: "fork.knife"
        case .medicacion: "syringe"
        case .salud: "cross.case"
        case .correlaciones: "chart.xyaxis.line"
        case .enlaces: "link.badge.plus"
        case .casa: "house.and.flag"
        case .compra: "cart"
        case .moda: "tshirt"
        case .mascota: "pawprint"
        case .vehiculo: "car"
        case .suscripciones: "repeat"
        case .prestamos: "creditcard.and.123"
        case .lecturas: "book"
        case .viajes: "airplane"
        case .tramites: "building.columns"
        case .personas: "person.2"
        case .documentos: "doc.on.doc"
        case .finanzas: "eurosign.circle"
        case .gastos: "creditcard"
        case .notas: "doc.text"
        case .bases: "square.grid.3x3"
        case .grafo: "point.3.connected.trianglepath.dotted"
        case .lienzo: "rectangle.on.rectangle.angled"
        case .avisos: "bell"
        case .ajustes: "gearshape"
        }
    }
}

/// Secciones de la barra lateral. Mi día, Planificar semana y Tareas salen como una sola entrada, Agenda (`Screen.agendaModes`).
struct SidebarSection { let title: String; let color: Color; let screens: [Screen] }

extension Screen {
    /// Los modos Día, Semana y Lista de la Agenda.
    static let agendaModes: [Screen] = [.dia, .planificar, .tareas]
    var agendaLabel: String {
        switch self {
        case .dia: "Día"
        case .planificar: "Semana"
        default: "Lista"
        }
    }

    static let sections = [
        SidebarSection(title: "Día a día", color: Brand.accent, screens: [.dia, .calendario, .semana, .mes, .proyectos, .objetivos]),
        SidebarSection(title: "Cuerpo", color: Brand.violet, screens: [.peso, .nutricion, .medicacion, .salud, .correlaciones]),
        SidebarSection(title: "Dinero", color: Brand.sky, screens: [.finanzas, .gastos, .suscripciones, .prestamos]),
        SidebarSection(title: "Hogar y vida", color: Brand.amber, screens: [.casa, .compra, .moda, .mascota, .vehiculo, .personas, .documentos, .tramites]),
        SidebarSection(title: "Ocio", color: Brand.rose, screens: [.viajes, .lecturas]),
        SidebarSection(title: "Conocimiento", color: Brand.info, screens: [.notas, .bases, .grafo, .lienzo, .enlaces]),
        SidebarSection(title: "Sistema", color: Brand.slate, screens: [.avisos, .ajustes]),
    ]

    /// Entrada de la barra lateral que la representa: los modos de la Agenda, la Agenda.
    var sidebarEntry: Screen { Screen.agendaModes.contains(self) ? .dia : self }
    var section: SidebarSection? { Screen.sections.first { $0.screens.contains(sidebarEntry) } }
    var color: Color { section?.color ?? Brand.accent }
}

/// Pantallas fijadas arriba de la barra lateral. Son también los atajos ⌘2…⌘9 (⌘1 es Inicio), así que no cambian al ocultar módulos.
enum Pins {
    static let key = "pinnedScreens"
    static let standard = [Screen.dia, .calendario, .notas].map(\.rawValue).joined(separator: "|")

    static func parse(_ raw: String) -> [Screen] {
        var out: [Screen] = []
        for part in raw.split(separator: "|") {
            guard let s = Screen(rawValue: String(part))?.sidebarEntry, s != .inicio, !out.contains(s) else { continue }
            out.append(s)
        }
        return out
    }

    /// Fija la pantalla si no lo estaba, o la quita.
    static func toggled(_ raw: String, _ s: Screen) -> String {
        var list = parse(raw)
        if let i = list.firstIndex(of: s.sidebarEntry) { list.remove(at: i) } else { list.append(s.sidebarEntry) }
        return list.map(\.rawValue).joined(separator: "|")
    }
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    /// Secciones plegadas de la barra lateral, separadas por «|». Se recuerdan al reabrir.
    @AppStorage("sidebarCollapsed") private var collapsedRaw = ""
    @AppStorage(Pins.key) private var pinnedRaw = Pins.standard
    /// Panel «Hoy» de la derecha (⌥⌘0).
    @AppStorage("todayPanel") private var panelOn = true
    /// Si cabe el panel junto a la pantalla; en una ventana estrecha se esconde solo, sin cambiar la preferencia.
    @State private var wide = true

    private var current: Screen { store.screen.flatMap { store.isVisible($0) ? $0 : nil } ?? .inicio }
    /// Calendario ya tiene su propio panel del día.
    private var panelShown: Bool { panelOn && wide && current != .calendario }

    var body: some View {
        let _ = BodyCounter.hit("ContentView")
        @Bindable var store = store
        if !store.isValid || (!store.modulesConfigured && store.looksNew) {
            WelcomeView()
        } else {
            let peek = panelShown && current != .notas
            NavigationSplitView {
                List(selection: selection) {
                    row(.inicio, color: Brand.accent)
                    let pins = Pins.parse(pinnedRaw).filter(store.isVisible)
                    if !pins.isEmpty {
                        Section("Fijadas") { ForEach(pins) { row($0, color: $0.color) } }
                    }
                    RecentNotesSection()
                    ForEach(Screen.sections.map { SidebarSection(title: $0.title, color: $0.color, screens: $0.screens.filter(store.isVisible)) }.filter { !$0.screens.isEmpty }, id: \.title) { sec in
                        Section(isExpanded: expanded(sec.title)) {
                            ForEach(sec.screens) { row($0, color: sec.color) }
                        } header: { header(sec) }
                    }
                }
                .navigationSplitViewColumnWidth(min: 190, ideal: 210)
                .safeAreaInset(edge: .bottom) { footer.padding(10) }
            } detail: {
                HStack(spacing: 0) {
                    // El banner y el aviso de «guardado» son vistas aparte: cambian con cada edición, y si los leyera esta vista
                    // se repintaría entera (barra lateral y pantalla) con cada cambio. Lo mismo el panel de la derecha.
                    VStack(spacing: 0) {
                        MessageBanner()
                        ScreenView(screen: current)
                    }
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottom) { UndoToast() }
                    if panelShown {
                        Divider()
                        HoyPanel().frame(width: 300).transition(.move(edge: .trailing))
                    }
                }
                .onGeometryChange(for: Bool.self) { $0.size.width >= 900 } action: { wide = $0 }
                .navigationTitle(Screen.agendaModes.contains(current) ? "Agenda" : store.title(current))
                .navigationSubtitle(current == .inicio ? "" : current.section?.title ?? "")
                .toolbar { toolbar }
            }
            .onChange(of: store.pendingNote) { if store.pendingNote != nil { store.screen = .notas } }
            // «Ver la nota al lado» con el panel oculto: se abre el panel o, si no cabe o es el Calendario, la nota en Notas.
            .onChange(of: store.peekNote) {
                guard let p = store.peekNote, !panelShown else { return }
                if wide && current != .calendario { withAnimation(.snappy) { panelOn = true } } else { store.peekNote = nil; store.pendingNote = p }
            }
            .environment(\.openURL, OpenURLAction { store.open(link: $0, peek: peek) })
            .sheet(isPresented: $store.showPalette) { CommandPalette() }
            .sheet(isPresented: $store.showQuickAdd) { QuickAddSheet() }
            .sheet(isPresented: $store.showCierre) { CierreSheet() }
            .sheet(isPresented: $store.showEmpezar) { EmpezarSheet() }
        }
    }

    /// La Agenda es una sola fila para sus tres modos: elegirla vuelve al último modo usado.
    private var selection: Binding<Screen?> {
        Binding(get: { store.screen?.sidebarEntry }, set: { if let new = $0 { store.go(new) } })
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { store.goBack() } label: { Label("Atrás", systemImage: "chevron.left") }
                .disabled(!store.canGoBack).help("Atrás (⌘[)")
            Button { store.goForward() } label: { Label("Adelante", systemImage: "chevron.right") }
                .disabled(!store.canGoForward).help("Adelante (⌘])")
        }
        if Screen.agendaModes.contains(current) {
            ToolbarItem(placement: .principal) {
                Picker("Vista de la agenda", selection: Binding(get: { current }, set: { store.screen = $0 })) {
                    ForEach(Screen.agendaModes) { Text($0.agendaLabel).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            FocusPill()
            Button { store.showPalette = true } label: { Label("Buscar", systemImage: "magnifyingglass") }.help("Buscar u orden rápida (⌘K)")
            Button { store.showQuickAdd = true } label: { Label("Añadir", systemImage: "plus") }.help("Captura rápida (⇧⌘N)")
            Button { withAnimation(.snappy) { panelOn.toggle() } } label: { Label("Panel Hoy", systemImage: "sidebar.right") }
                .help(panelOn ? "Ocultar el panel Hoy (⌥⌘0)" : "Mostrar el panel Hoy (⌥⌘0)")
        }
    }

    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: "|").map(String.init)) }

    private func expanded(_ title: String) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(title) }, set: { open in
            var c = collapsed
            if open { c.remove(title) } else { c.insert(title) }
            collapsedRaw = c.sorted().joined(separator: "|")
        })
    }

    /// Plegada, la sección suma los contadores de sus pantallas para que no se pierda nada pendiente.
    private func header(_ sec: SidebarSection) -> some View {
        let total = sec.screens.reduce(0) { $0 + (store.sidebar.counts[countKey($1)] ?? 0) }
        return HStack {
            Text(sec.title)
            Spacer()
            if collapsed.contains(sec.title), total > 0 { Text("\(total)").monospacedDigit().foregroundStyle(.secondary) }
        }
    }

    /// La Agenda enseña el número de Tareas (lo de hoy y lo vencido).
    private func countKey(_ s: Screen) -> Screen { s == .dia ? .tareas : s }

    private func row(_ s: Screen, color: Color) -> some View {
        let pinned = Pins.parse(pinnedRaw).contains(s)
        return Label { Text(s == .dia ? "Agenda" : store.title(s)) } icon: { Image(systemName: s == .dia ? "calendar.day.timeline.left" : s.icon).foregroundStyle(color) }
            .badge(badge(s))
            .tag(s)
            .contextMenu {
                if s != .inicio {
                    Button(pinned ? "Quitar de Fijadas" : "Fijar arriba") { pinnedRaw = Pins.toggled(pinnedRaw, s) }
                }
                Button("Abrir en otra ventana") { openWindow(id: "pantalla", value: s) }
            }
    }

    /// Agenda en rojo si hay tareas vencidas; Medicación dice «hoy» o «tarde» en vez de un número.
    private func badge(_ s: Screen) -> Text? {
        let state = store.sidebar   // publicado: solo avisa si cambia algún indicador
        if s == .medicacion, let d = state.medicationDays, d <= 0 { return Text(d == 0 ? "hoy" : "tarde").foregroundStyle(d == 0 ? Brand.warn : Brand.bad) }
        guard let n = state.counts[countKey(s)] else { return nil }
        return Text("\(n)").foregroundStyle(countKey(s) == .tareas && state.tasksOverdue ? Brand.bad : .secondary)
    }

    private var footer: some View {
        HStack {
            Label(store.vaultName, systemImage: "externaldrive").font(.caption).foregroundStyle(.secondary).lineLimit(1).help(store.root.path)
            Spacer()
        }
    }
}

/// Las últimas notas abiertas, debajo de las fijadas. Vista aparte: lee la lista de notas, que cambia al crear una.
private struct RecentNotesSection: View {
    @Environment(Store.self) private var store
    @AppStorage("recentNotes") private var recentRaw = ""

    var body: some View {
        let paths = Set(store.notes.map(\.path))
        let list = Array(recentRaw.split(separator: "\n").map(String.init).filter(paths.contains).prefix(3))
        if !list.isEmpty {
            Section("Recientes") {
                ForEach(list, id: \.self) { p in
                    Button { store.pendingNote = p } label: {
                        Label(((p as NSString).lastPathComponent as NSString).deletingPathExtension, systemImage: "doc.text")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// La pantalla `screen`. La usan la ventana principal y las ventanas aparte («Abrir en otra ventana»).
struct ScreenView: View {
    @Environment(Store.self) private var store
    let screen: Screen

    var body: some View {
        switch screen {
        case .inicio: InicioView(go: { store.screen = $0 })
        case .dia: MiDiaView()
        case .tareas: TareasView()
        case .calendario: CalendarioView()
        case .planificar: PlanificarView()
        case .semana: SemanaView()
        case .mes: MesView()
        case .proyectos: ProyectosView()
        case .objetivos: ObjetivosView()
        case .peso: PesoView()
        case .nutricion: NutricionView()
        case .medicacion: MedicacionView()
        case .salud: SaludView()
        case .correlaciones: CorrelacionesView()
        case .enlaces: EnlacesView()
        case .casa: CasaView()
        case .compra: CompraView()
        case .moda: ModaView()
        case .mascota: MascotaView()
        case .vehiculo: VehiculoView()
        case .suscripciones: SuscripcionesView()
        case .prestamos: PrestamosView()
        case .lecturas: LecturasView()
        case .viajes: ViajesView()
        case .tramites: TramitesView()
        case .personas: PersonasView()
        case .documentos: DocumentosView()
        case .finanzas: FinanzasView()
        case .gastos: GastosView()
        case .notas: NotasView()
        case .bases: BasesView()
        case .grafo: GrafoView()
        case .lienzo: LienzoView()
        case .avisos: RemindersView()
        case .ajustes: AjustesView()
        }
    }
}

/// Cuenta atrás del bloque de enfoque, en la barra de herramientas. Solo esta vista se repinta cada segundo.
private struct FocusPill: View {
    @Environment(Store.self) private var store

    var body: some View {
        if let f = store.focus {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = max(0, Int(f.end.timeIntervalSince(ctx.date).rounded(.up)))
                Button { store.stopFocus() } label: {
                    Label("\(left / 60):\(String(format: "%02d", left % 60)) · \(f.title.prefix(28))", systemImage: "timer")
                        .labelStyle(.titleAndIcon).monospacedDigit()
                }
                .help("Enfoque en marcha. Pulsa para pararlo.")
            }
        }
    }
}

/// Mensaje de arriba (errores, avisos de una acción). Lee `store.message` solo esta vista.
private struct MessageBanner: View {
    @Environment(Store.self) private var store

    var body: some View {
        if let m = store.message {
            HStack { Text(m).font(.callout); Spacer(); Button("Cerrar") { store.message = nil }.buttonStyle(.accentLink) }
                .padding(.horizontal, 14).padding(.vertical, 8).background(Brand.warn.opacity(0.2))
        }
    }
}

/// «Guardado en …» con el botón de deshacer, abajo. Lee `store.lastChange` solo esta vista.
private struct UndoToast: View {
    @Environment(Store.self) private var store

    var body: some View {
        if let c = store.lastChange {
            HStack(spacing: 12) {
                Image(systemName: c.undoable ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill").foregroundStyle(Brand.accent)
                Text(c.undoable ? "Guardado en \(((c.file as NSString).lastPathComponent as NSString).deletingPathExtension)" : c.file)
                if c.undoable { Button("Deshacer") { store.undo() }.buttonStyle(.accentLink) }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: c.id) {
                try? await Task.sleep(for: .seconds(6))
                withAnimation { store.dismissChange(c.id) }
            }
        }
    }
}
