import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Módulos, plantillas y asistente del principio

private func starter(_ key: String, name: String? = nil) throws -> String { try #require(Starter.text(forKey: key, name: name)) }

@Test func everyModuleNoteHasATemplate() {
    for m in Module.allCases {
        #expect(!m.screens.isEmpty && !m.files.isEmpty, "\(m)")
        for key in m.files { #expect(Starter.text(forKey: key) != nil, "\(key)") }
    }
    // cada pantalla está en un solo módulo; las de la base no tienen módulo
    let screens = Module.allCases.flatMap(\.screens)
    #expect(Set(screens).count == screens.count)
    #expect(Module.of(.tareas) == nil && Module.of(.gastos) == .finanzas && Module.of(.nala) == .mascota)
}

@Test func emptyTemplatesTakeTheFirstEntry() throws {
    let day = try #require(DayKey.date("2026-10-20"))
    // peso: la primera fila entra aunque la tabla esté vacía
    let peso = try #require(Edit.addWeight(try starter("peso"), date: day, kg: 92.4, note: "primera"))
    let w = Parse.weight(peso)
    #expect(w.records.count == 1 && w.records[0].kg == 92.4 && w.initialKg == 92.4 && w.goalKg == 0)
    #expect(Edit.addWeight(peso, date: DayKey.adding(days: 1, to: day), kg: 92, note: "").map { Parse.weight($0).records.count } == 2)
    // medicación, con su nombre
    let med = try #require(Edit.addDose(try starter("mounjaro", name: "Ozempic"), date: day, dose: 0.5, site: "Abdomen", note: ""))
    let m = Parse.mounjaro(med)
    #expect(m.name == "Ozempic" && m.everyDays == 7 && m.doses.count == 1 && m.doses[0].site == "Abdomen")
    // mascota
    let pet = try #require(Edit.addNalaVisit(try starter("nala", name: "Luna"), date: day, tipo: "Vacuna", detalle: "Rabia", proxima: DayKey.adding(days: 365, to: day), coste: "40"))
    let n = Parse.nala(pet)
    #expect(n.name == "Luna" && n.visits.count == 1 && n.visits[0].proxima != nil)
    // casa: las cuatro tablas y añadir filas en reformas y compras
    let casa = try starter("casa")
    let c = Parse.casa(casa)
    #expect(c.reformas.header.first == "Qué" && c.compras.header.contains("Precio estimado") && !c.electros.header.isEmpty && !c.small.header.isEmpty)
    let reforma = try #require(Edit.addRow(casa, section: "Reformas", cells: ["Pintar", "Salón", "Media", "300", "", "Idea"]))
    #expect(Parse.casa(reforma).reformas.rows.filter { !($0.cells.first ?? "").isEmpty }.count == 1)
    // salud: citas, tratamientos y análisis
    var salud = try starter("medico")
    salud = try #require(Edit.appendToSection(salud, section: "Próximas citas", line: "- [ ] Dentista 📅 2026-11-02"))
    salud = try #require(Edit.appendToSection(salud, section: "Tratamientos", line: "- Vitamina D"))
    #expect(Parse.tasks(salud, file: "x").first?.text == "Dentista" && Parse.listItems(salud, section: "Tratamientos").map(\.text) == ["Vitamina D"])
    #expect(Parse.tables(salud).contains { MD.fold($0.title).contains("analisis") })
    // plan: tres comidas sin números todavía, y la cabecera que la pantalla salta
    let plan = Parse.plan(try starter("plan"))
    #expect(plan.meals.count == 4 && plan.meals[0][0] == "Comida" && plan.kcal == 0)
    // personas, documentos, objetivos, ropa, medidas
    #expect(Parse.people(try starter("personas")).table != nil)
    #expect(Parse.tables(try starter("documentos")).filter { $0.col("caduca") != nil }.count == 2)
    #expect(Parse.tables(try starter("objetivos")).contains { $0.col("objetivo") != nil })
    #expect(try starter("objetivos").contains("**Trimestre:**"))
    let moda = Parse.tables(try starter("moda"))
    #expect(moda.contains { MD.fold($0.title).contains("por comprar") && $0.col("estado") != nil } && moda.contains { MD.fold($0.title) == "armario" })
    #expect(Measures.parse(try starter("medidas")).table != nil)
    // finanzas: los objetivos de ahorro son tareas de su sección
    let fin = try #require(Edit.appendToSection(try starter("finanzas"), section: "Objetivos de ahorro y pagos", line: "- [ ] Fondo de 3 meses"))
    #expect(Parse.tasks(fin, file: "x").count == 1)
    // ninguna plantilla trae tareas ni enlaces rotos de ejemplo
    for m in Module.allCases {
        for k in m.files {
            let t = try starter(k)
            #expect(Parse.tasks(t, file: k).isEmpty && Links.extract(t).isEmpty, "\(k)")
        }
    }
}

@Test func namesKeepTheOldNotesAndAreGenericWithoutOne() {
    #expect(Parse.mounjaro(mounjaroFixture).name == "Mounjaro")   // notas de antes, sin «nombre:»
    #expect(Parse.mounjaro("").name == "Medicación" && Parse.nala("").name == "Mascota")
    #expect(Parse.nala("---\nnacimiento: 01/01/2020\n---\n").name == "Nala")
    #expect(Parse.nala("---\nnombre: \"Luna: la gata\"\n---\n").name == "Luna: la gata")
    #expect(Starter.yaml("Luna: la gata") == "\"Luna: la gata\"" && Starter.yaml("Ozempic") == "Ozempic")
}

@MainActor @Test func wizardSetsUpAnEmptyFolder() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("nuevo-\(UUID().uuidString)")
    let root = tmp.appendingPathComponent("Mis notas")   // aún no existe
    let store = Store(root: root, backups: tmp.appendingPathComponent("Copias"))
    #expect(!store.isValid && store.looksNew && !store.modulesConfigured)
    store.setUp(modules: [.peso, .mascota, .finanzas], petName: "Luna", medication: nil)
    defer { UserDefaults.standard.removeObject(forKey: "starterPet") }
    #expect(store.isValid && store.modulesConfigured && !store.looksNew)
    #expect(store.exists(VaultPath.peso) && store.exists(VaultPath.nala) && store.exists(VaultPath.finanzas) && store.exists(VaultPath.inbox))
    #expect(!store.exists(VaultPath.casa) && !store.exists(VaultPath.mounjaro))
    #expect(store.hiddenModules == Set(Module.allCases).subtracting([.peso, .mascota, .finanzas]))
    #expect(store.title(.nala) == "Luna" && store.title(.mounjaro) == "Medicación" && store.title(.tareas) == "Tareas")
    #expect(store.isVisible(.peso) && store.isVisible(.gastos) && !store.isVisible(.casa) && store.isVisible(.notas))
    #expect(store.undoStack.isEmpty)   // crear las notas del principio no es un cambio que deshacer
    // volver a pasar por el asistente no pisa lo que ya hay
    store.addWeight(date: DayKey.today(), kg: 80, note: "")
    store.setUp(modules: [.peso, .casa])
    #expect(store.weight.records.count == 1 && store.exists(VaultPath.casa))
}

@MainActor @Test func firstEntryCreatesTheModuleNoteAndUndoRemovesIt() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("auto-\(UUID().uuidString)")
    let root = tmp.appendingPathComponent("V")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "# Algo\n".write(to: root.appendingPathComponent("Algo.md"), atomically: true, encoding: .utf8)
    let store = Store(root: root, backups: tmp.appendingPathComponent("Copias"))
    #expect(store.missingFiles(.peso) == [VaultPath.peso])
    store.addWeight(date: DayKey.today(), kg: 101.5, note: "")
    #expect(store.message == nil && store.weight.last?.kg == 101.5 && store.missingFiles(.peso).isEmpty)
    store.addDose(date: DayKey.today(), dose: 2.5, site: "Muslo", note: "")
    #expect(store.mounjaro.doses.count == 1 && store.mounjaro.name == "Medicación")
    store.addCasaRow(section: "Compras", cells: ["Sofá", "Salón", "Alta", "900", "", ""])
    #expect(store.casa.compras.rows.contains { $0.cells.first == "Sofá" })
    store.undo(); store.undo(); store.undo()
    #expect(!store.exists(VaultPath.peso) && !store.exists(VaultPath.mounjaro) && !store.exists(VaultPath.casa))
    // una nota que no es de ningún módulo sigue sin crearse sola
    #expect(!store.edit("Otra.md") { $0 + "x" } && store.message == "No se pudo leer Otra.md.")
}

@MainActor @Test func hiddenModulesDropTheirAlerts() throws {
    let store = Store(root: try syntheticVault())
    let today = try #require(DayKey.date("2026-10-30"))   // el pinchazo del 09/10 va tarde
    #expect(store.alerts(today: today).contains { $0.screen == .mounjaro })
    store.hiddenModules = [.medicacion]
    #expect(!store.alerts(today: today).contains { $0.screen == .mounjaro })
    #expect(!store.isVisible(.mounjaro) && store.isVisible(.peso))
}

@MainActor @Test func pathOverridesMoveAModule() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ruta-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp.appendingPathComponent("Salud"), withIntermediateDirectories: true)
    try "| Fecha | Peso |\n|--|--|\n| 01/10/2026 | 70 |\n".write(to: tmp.appendingPathComponent("Salud/Báscula.md"), atomically: true, encoding: .utf8)
    // clave inventada para no tocar las rutas que leen los demás tests a la vez
    VaultPath.setOverride("clave-modulos", "Salud/Báscula.md")
    defer { VaultPath.setOverride("clave-modulos", nil) }
    #expect(VaultPath.overrides["clave-modulos"] == "Salud/Báscula.md" && VaultPath.path("clave-modulos") == "Salud/Báscula.md")
    VaultPath.setOverride("clave-modulos", nil)
    #expect(VaultPath.overrides["clave-modulos"] == nil && VaultPath.path("clave-modulos") == "clave-modulos")
}

@MainActor @Test func setupScreensRender() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vista-\(UUID().uuidString)")
    let store = Store(root: tmp.appendingPathComponent("V"), backups: tmp.appendingPathComponent("C"))
    for view in [AnyView(WelcomeView()), AnyView(ContentView()), AnyView(ModulesCard()), AnyView(MissingNoteBanner(module: .peso)), AnyView(PesoView())] {
        let r = ImageRenderer(content: view.environment(store).frame(width: 1000, height: 800))
        #expect(r.cgImage != nil)
    }
}

@Test func newFoldersGetNeutralPathsButOldNotesKeepTheirs() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rutas-\(UUID().uuidString)")
    let fresh = VaultPath.freshOverrides(root: root)   // la carpeta ni existe
    #expect(fresh["peso"] == "Salud/Peso.md" && fresh["nala"] == "Mascota/Mascota.md" && fresh["mounjaro"] == "Salud/Medicación.md")
    #expect(fresh["casa"] == nil && fresh["inbox"] == nil)   // las que no eran personales no cambian
    #expect(fresh.values.allSatisfy { !$0.contains("Cambio físico") && !$0.contains("Nala") })
    // una carpeta con notas de antes conserva esas rutas, también si iCloud aún no las ha descargado
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Cambio físico"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Nala"), withIntermediateDirectories: true)
    try "x".write(to: root.appendingPathComponent("Cambio físico/Peso.md"), atomically: true, encoding: .utf8)
    try "x".write(to: root.appendingPathComponent("Nala/.Nala.md.icloud"), atomically: true, encoding: .utf8)
    let mixed = VaultPath.freshOverrides(root: root)
    #expect(mixed["peso"] == nil && mixed["nala"] == nil && mixed["mounjaro"] == "Salud/Medicación.md")
    // lo que va junto a cada nota sigue su carpeta
    #expect(VaultPath.beside("peso", "Fotos") == "Cambio físico/Fotos" && VaultPath.folder("medico") == "Organización/Médico")
}
