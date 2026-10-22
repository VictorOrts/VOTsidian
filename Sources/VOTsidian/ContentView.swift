import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case inicio = "Inicio", tareas = "Tareas", calendario = "Calendario", planificar = "Planificar semana", semana = "Revisión semanal", mes = "Revisión mensual", proyectos = "Proyectos", objetivos = "Objetivos"
    case peso = "Peso", nutricion = "Plan nutricional", mounjaro = "Mounjaro", salud = "Salud y médicos", correlaciones = "Correlaciones"
    case casa = "Casa", compra = "Compra", moda = "Moda", nala = "Nala", personas = "Personas", documentos = "Documentos", finanzas = "Finanzas"
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
        case .mounjaro: "syringe"
        case .salud: "cross.case"
        case .correlaciones: "chart.xyaxis.line"
        case .enlaces: "link.badge.plus"
        case .casa: "house.and.flag"
        case .compra: "cart"
        case .moda: "tshirt"
        case .nala: "cat"
        case .personas: "person.2"
        case .documentos: "doc.on.doc"
        case .finanzas: "eurosign.circle"
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

    var body: some View {
        @Bindable var store = store
        if !store.isValid {
            ContentUnavailableView {
                Label("No encuentro tu vault", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Busqué \(store.root.path). Elige la carpeta de tus notas, la que tiene tus notas (por ejemplo Cambio físico/Peso.md).")
            } actions: {
                Button("Elegir carpeta…") { store.chooseFolder() }
            }
        } else {
            NavigationSplitView {
                List(selection: $store.screen) {
                    row(.inicio)
                    Section("Día a día") { row(.tareas); row(.calendario); row(.planificar); row(.semana); row(.mes); row(.proyectos); row(.objetivos) }
                    Section("Cuerpo") { row(.peso); row(.nutricion); row(.mounjaro); row(.salud); row(.correlaciones) }
                    Section("Hogar y vida") { row(.casa); row(.compra); row(.moda); row(.nala); row(.personas); row(.documentos); row(.finanzas) }
                    Section("Conocimiento") { row(.notas); row(.bases); row(.grafo); row(.enlaces) }
                    Section("Sistema") { row(.avisos); row(.ajustes) }
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
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
        switch store.screen ?? .inicio {
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
        case .mounjaro: MounjaroView()
        case .salud: SaludView()
        case .correlaciones: CorrelacionesView()
        case .enlaces: EnlacesView()
        case .casa: CasaView()
        case .compra: CompraView()
        case .moda: ModaView()
        case .nala: NalaView()
        case .personas: PersonasView()
        case .documentos: DocumentosView()
        case .finanzas: FinanzasView()
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

    private func row(_ s: Screen) -> some View { Label(s.rawValue, systemImage: s.icon).tag(s) }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { store.showQuickAdd = true } label: { Label("Añadir", systemImage: "plus") }.help("Captura rápida (⇧⌘N)")
                Button { store.showPalette = true } label: { Image(systemName: "magnifyingglass").accessibilityLabel("Buscar") }.help("Buscar (⌘K)")
                Button { store.reload() } label: { Image(systemName: "arrow.clockwise").accessibilityLabel("Recargar") }.help("Recargar")
            }.controlSize(.small).buttonStyle(.glass)
            AppearancePicker().controlSize(.small)
            Label(store.vaultName, systemImage: "externaldrive").font(.caption).foregroundStyle(.secondary)
        }
    }
}
