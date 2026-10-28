import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Humo: cada pantalla se construye y se pinta sin fallar

/// Pinta todas las pantallas con los datos de `store`: si alguna vista no aguanta los datos, falla.
/// Muy alto: las pantallas largas van en `LazyVStack`, y con 800 pt las tarjetas de abajo no se construían (ni se probaban).
@MainActor func renderAllScreens(_ store: Store) throws {
    func render<V: View>(_ name: String, _ view: V, size: CGSize = CGSize(width: 1000, height: 6000)) throws {
        let r = ImageRenderer(content: view.environment(store).frame(width: size.width, height: size.height))
        r.scale = 1
        #expect(r.cgImage != nil, "\(name) no se pudo pintar")
    }
    for screen in Screen.allCases {
        switch screen {
        case .inicio: try render("Inicio", InicioView(go: { _ in }))
        case .dia: try render("Mi día", MiDiaView())
        case .tareas: try render("Tareas", TareasView())
        case .calendario:
            try render("Calendario", CalendarioView())
            UserDefaults.standard.set(true, forKey: "calendarWeek")
            defer { UserDefaults.standard.removeObject(forKey: "calendarWeek") }
            try render("Calendario semana", CalendarioView())
        case .planificar: try render("Planificar", PlanificarView())
        case .semana: try render("Semana", SemanaView())
        case .mes: try render("Mes", MesView())
        case .proyectos: try render("Proyectos", ProyectosView())
        case .objetivos: try render("Objetivos", ObjetivosView())
        case .peso: try render("Peso", PesoView())
        case .nutricion: try render("Nutrición", NutricionView())
        case .medicacion: try render("Medicacion", MedicacionView())
        case .salud: try render("Salud", SaludView())
        case .correlaciones: try render("Correlaciones", CorrelacionesView())
        case .casa: try render("Casa", CasaView())
        case .compra: try render("Compra", CompraView())
        case .moda: try render("Moda", ModaView())
        case .mascota: try render("Mascota", MascotaView())
        case .vehiculo: try render("Vehículo", VehiculoView())
        case .suscripciones: try render("Suscripciones", SuscripcionesView())
        case .prestamos: try render("Préstamos", PrestamosView())
        case .lecturas: try render("Lecturas", LecturasView())
        case .viajes: try render("Viajes", ViajesView())
        case .tramites: try render("Trámites", TramitesView())
        case .personas: try render("Personas", PersonasView())
        case .documentos: try render("Documentos", DocumentosView())
        case .finanzas: try render("Finanzas", FinanzasView())
        case .gastos: try render("Gastos", GastosView())
        case .notas: try render("Notas", NotasView())
        case .bases: try render("Bases", BasesView())
        case .grafo: try render("Grafo", GrafoView())
        case .lienzo: try render("Lienzo", LienzoView())
        case .enlaces: try render("Enlaces", EnlacesView())
        case .avisos: try render("Avisos", RemindersView())
        case .ajustes: try render("Ajustes", AjustesView())
        }
    }
}


@MainActor @Test func everyScreenRenders() throws {
    // Con VAULT_COPY usa tus notas; si no, un vault sintético para que el humo también corra en CI.
    let store = Store(root: try ProcessInfo.processInfo.environment["VAULT_COPY"].map(tempVaultCopy) ?? syntheticVault())
    store.createSampleTemplates()
    store.setDiaryValue(DayKey.today(), "sueno_h", 7)
    store.appendToDiary(DayKey.today(), text: "prueba")
    _ = store.createNote(folder: "Casa", name: "Con incrustados", template: "En blanco")
    store.edit("Casa/Con incrustados.md") { $0 + "![[Peso#Registro]]\n\n![[Mascota]]\n" }
    try renderAllScreens(store)
    func render<V: View>(_ name: String, _ view: V, size: CGSize = CGSize(width: 1000, height: 800)) throws {
        let r = ImageRenderer(content: view.environment(store).frame(width: size.width, height: size.height))
        r.scale = 1
        #expect(r.cgImage != nil, "\(name) no se pudo pintar")
    }
    try render("Cierre", CierreSheet(), size: CGSize(width: 660, height: 500))
    try render("Empezar", EmpezarSheet(), size: CGSize(width: 660, height: 560))
    if let t = store.tasks.first(where: { !$0.done }) {
        try render("Ficha de tarea", EventPanel(event: EventRef(id: "t\(t.id)", title: t.text, kind: .task, date: DayKey.today(), minutes: 600, task: t)) {}, size: CGSize(width: 380, height: 360))
    }
    try render("Ficha fija", EventPanel(event: EventRef(id: "b", title: "Cumpleaños de Ana", kind: .birthday, date: DayKey.today(), screen: .personas)) {}, size: CGSize(width: 380, height: 200))
    try render("Captura", QuickAddSheet(), size: CGSize(width: 460, height: 300))
    try render("Palette", CommandPalette(), size: CGSize(width: 680, height: 500))
    try render("MenuBar", MenuBarPanel(), size: CGSize(width: 340, height: 600))
    try render("NuevaNota", NewNoteSheet(folders: ["Casa"]) { _ in }, size: CGSize(width: 480, height: 420))
    try render("Nota con incrustados", NoteBody(text: store.read("Casa/Con incrustados.md"), actions: NoteActions(toggle: { _, _ in }, editRow: { _ in }, addRow: { _ in }, setProperty: { _, _ in })), size: CGSize(width: 700, height: 600))
}
