import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case inicio = "Inicio", tareas = "Tareas", calendario = "Calendario", planificar = "Planificar semana", semana = "Revisión semanal", mes = "Revisión mensual", proyectos = "Proyectos", objetivos = "Objetivos"
    case peso = "Peso", nutricion = "Plan nutricional", medicacion = "Medicación", salud = "Salud y médicos", correlaciones = "Correlaciones"
    case casa = "Casa", compra = "Compra", moda = "Moda", mascota = "Mascota", vehiculo = "Vehículo", personas = "Personas", documentos = "Documentos", finanzas = "Finanzas", gastos = "Gastos"
    case suscripciones = "Suscripciones", prestamos = "Préstamos", lecturas = "Lecturas", viajes = "Viajes"
    case notas = "Notas", bases = "Bases", grafo = "Grafo", enlaces = "Enlaces rotos", avisos = "Avisos", ajustes = "Ajustes"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .inicio: "house"
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
        case .personas: "person.2"
        case .documentos: "doc.on.doc"
        case .finanzas: "eurosign.circle"
        case .gastos: "creditcard"
        case .notas: "doc.text"
        case .bases: "square.grid.3x3"
        case .grafo: "point.3.connected.trianglepath.dotted"
        case .avisos: "bell"
        case .ajustes: "gearshape"
        }
    }
}

struct ContentView: View {
    @Environment(Store.self) private var store
    /// Secciones plegadas de la barra lateral, separadas por «|». Se recuerdan al reabrir.
    @AppStorage("sidebarCollapsed") private var collapsedRaw = ""
    @State private var counts: [Screen: Int] = [:]

    private struct SidebarSection { let title: String; let color: Color; let screens: [Screen] }
    private static let sections = [
        SidebarSection(title: "Día a día", color: Brand.accent, screens: [.tareas, .calendario, .planificar, .semana, .mes, .proyectos, .objetivos]),
        SidebarSection(title: "Cuerpo", color: Brand.violet, screens: [.peso, .nutricion, .medicacion, .salud, .correlaciones]),
        SidebarSection(title: "Dinero", color: Brand.sky, screens: [.finanzas, .gastos, .suscripciones, .prestamos]),
        SidebarSection(title: "Hogar y vida", color: Brand.amber, screens: [.casa, .compra, .moda, .mascota, .vehiculo, .personas, .documentos]),
        SidebarSection(title: "Ocio", color: Brand.rose, screens: [.viajes, .lecturas]),
        SidebarSection(title: "Conocimiento", color: Brand.info, screens: [.notas, .bases, .grafo, .enlaces]),
        SidebarSection(title: "Sistema", color: Brand.slate, screens: [.avisos, .ajustes]),
    ]

    var body: some View {
        @Bindable var store = store
        if !store.isValid || (!store.modulesConfigured && store.looksNew) {
            WelcomeView()
        } else {
            NavigationSplitView {
                List(selection: $store.screen) {
                    row(.inicio, color: Brand.accent)
                    ForEach(Self.sections.map { SidebarSection(title: $0.title, color: $0.color, screens: $0.screens.filter(store.isVisible)) }.filter { !$0.screens.isEmpty }, id: \.title) { sec in
                        Section(isExpanded: expanded(sec.title)) {
                            ForEach(sec.screens) { row($0, color: sec.color) }
                        } header: { header(sec) }
                    }
                }
                .navigationSplitViewColumnWidth(min: 190, ideal: 210)
                .task(id: store.revision) { counts = store.sidebarCounts() }
                .safeAreaInset(edge: .bottom) { footer.padding(10) }
            } detail: {
                VStack(spacing: 0) {
                    if let m = store.message {
                        HStack { Text(m).font(.callout); Spacer(); Button("Cerrar") { store.message = nil }.buttonStyle(.accentLink) }
                            .padding(.horizontal, 14).padding(.vertical, 8).background(Brand.warn.opacity(0.2))
                    }
                    detail
                }
                .overlay(alignment: .bottom) { toast }
            }
            .onChange(of: store.pendingNote) { if store.pendingNote != nil { store.screen = .notas } }
            .environment(\.openURL, OpenURLAction { store.open(link: $0) })
            .sheet(isPresented: $store.showPalette) { CommandPalette() }
            .sheet(isPresented: $store.showQuickAdd) { QuickAddSheet() }
            .sheet(isPresented: $store.showCierre) { CierreSheet() }
        }
    }

    @ViewBuilder private var detail: some View {
        switch store.screen.flatMap({ store.isVisible($0) ? $0 : nil }) ?? .inicio {
        case .inicio: InicioView(go: { store.screen = $0 })
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
        case .personas: PersonasView()
        case .documentos: DocumentosView()
        case .finanzas: FinanzasView()
        case .gastos: GastosView()
        case .notas: NotasView()
        case .bases: BasesView()
        case .grafo: GrafoView()
        case .avisos: RemindersView()
        case .ajustes: AjustesView()
        }
    }

    @ViewBuilder private var toast: some View {
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
        let total = sec.screens.reduce(0) { $0 + (counts[$1] ?? 0) }
        return HStack {
            Text(sec.title)
            Spacer()
            if collapsed.contains(sec.title), total > 0 { Text("\(total)").monospacedDigit().foregroundStyle(.secondary) }
        }
    }

    private func row(_ s: Screen, color: Color) -> some View {
        Label { Text(store.title(s)) } icon: { Image(systemName: s.icon).foregroundStyle(color) }
            .badge(badge(s))
            .tag(s)
    }

    /// Tareas en rojo si hay vencidas; Medicación dice «hoy» o «tarde» en vez de un número.
    private func badge(_ s: Screen) -> Text? {
        if s == .medicacion, let d = store.medicacion.daysUntilNext, d <= 0 { return Text(d == 0 ? "hoy" : "tarde").foregroundStyle(d == 0 ? Brand.warn : Brand.bad) }
        guard let n = counts[s] else { return nil }
        let overdue = s == .tareas && store.tasks.contains { !$0.done && ($0.due.map { $0 < DayKey.today() } ?? false) }
        return Text("\(n)").foregroundStyle(overdue ? Brand.bad : .secondary)
    }

    private var footer: some View {
        HStack {
            Button { store.showQuickAdd = true } label: { Label("Añadir", systemImage: "plus") }.help("Captura rápida (⇧⌘N)")
            Button { store.showPalette = true } label: { Image(systemName: "magnifyingglass").accessibilityLabel("Buscar") }.help("Buscar (⌘K)")
            Spacer()
            Label(store.vaultName, systemImage: "externaldrive").font(.caption).foregroundStyle(.secondary).lineLimit(1).help(store.root.path)
        }
        .controlSize(.small).buttonStyle(.glass)
    }
}
