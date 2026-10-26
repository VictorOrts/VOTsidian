import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Contenido incrustado y plantillas con preguntas

@Test func embedHelpers() {
    #expect(Embed.target("Plan Nutricional#Reparto del día|alias") == ("Plan Nutricional", "Reparto del día"))
    #expect(Embed.target("Carpeta/Peso") == ("Peso", nil) && Embed.target("Peso#") == ("Peso", nil))
    #expect(Embed.isImage("foto.HEIC") && !Embed.isImage("nota.md"))
    let note = "---\ntipo: x\n---\n# Título\nIntro\n\n## Reparto\nlínea A\n### Detalle\nlínea B\n\n## Otro\nfuera\n"
    #expect(Embed.body(of: note, heading: nil).hasPrefix("# Título"))
    #expect(Embed.body(of: note, heading: "reparto") == "línea A\n### Detalle\nlínea B")     // incluye subsecciones, no la siguiente del mismo nivel
    #expect(Embed.body(of: note, heading: "Inexistente") == "")
    let blocks = MDParser.blocks("Antes\n\n![[Peso#Registro]]\n\n- ![[no]] es lista\n")
    if case .embed(let t) = blocks[1] { #expect(t == "Peso#Registro") } else { Issue.record("no es embed") }
    #expect(blocks.count == 3)
}

@MainActor @Test func templateQuestionsOnCopy() throws {
    guard let path = ProcessInfo.processInfo.environment["VAULT_COPY"] else { return }
    let store = Store(root: try tempVaultCopy(path))
    store.createSampleTemplates()
    #expect(store.templateQuestions("Reunión").map(\.label) == ["Con quién"])
    #expect(store.templateQuestions("Lectura").map(\.label) == ["Autor", "Estado"] && store.templateQuestions("Lectura")[1].defaultValue == "pendiente")
    #expect(store.templateQuestions("Viaje").count == 3)
    let rel = try #require(store.createNote(folder: "Proyectos", name: "Lisboa", template: "Viaje", answers: ["Destino": "Lisboa", "Fecha de salida (AAAA-MM-DD)": "2026-12-01"]))
    let text = store.read(rel)
    #expect(text.contains("**Destino:** Lisboa") && text.contains("fecha_inicio: 2026-12-01") && text.contains("fecha_fin: \n") && !text.contains("{{"))
    let lec = try #require(store.createNote(folder: "", name: "Un libro", template: "Lectura", answers: ["Autor": "Eco"]))
    #expect(store.read(lec).contains("autor: Eco") && store.read(lec).contains("estado: pendiente"))
    // incrustar: una nota con ![[…]] ve el contenido de otra
    store.edit("Casa/Casa.md") { $0 + "\n![[Peso#Registro]]\n" }
    #expect(store.noteTexts["Casa/Casa.md"]?.contains("![[Peso#Registro]]") == true)
    #expect(Embed.body(of: store.noteTexts[VaultPath.peso] ?? "", heading: "Registro").contains("|"))
}

// MARK: - Orden de las tarjetas de Inicio

@Test func homeLayoutLogic() {
    let std = HomeLayout.standard
    #expect(std.rows.map { $0.map(\.rawValue) } == [["atencion"], ["hoy"], ["peso", "medicacion"], ["tareas", "habitos"], ["mascota", "nutricion"], ["gastos", "vehiculo"], ["suscripciones", "prestamos"], ["viajes", "lecturas"], ["tramites"]])
    var l = HomeLayout(raw: "")
    #expect(l == std)
    l.move(.mascota, by: -10)                          // sube hasta el principio y no se sale
    #expect(l.items.first?.card == .mascota)
    l.setVisible(.peso, false); l.setVisible(.hoy, false)
    #expect(l.rows.flatMap { $0 }.contains(.peso) == false && l.rows.flatMap { $0 }.contains(.hoy) == false)
    let again = HomeLayout(raw: l.raw)
    #expect(again == l)                              // se guarda y se recupera igual
    // ids desconocidos se ignoran y las tarjetas nuevas se añaden al final
    let odd = HomeLayout(raw: "mascota:1,inventada:1,peso:0,peso:1")
    #expect(odd.items.count == HomeCard.allCases.count && odd.items[0].card == .mascota && odd.items[1] == (.peso, false))
    // una tarjeta mediana sola ocupa media fila
    var one = HomeLayout.standard
    for c in HomeCard.allCases where c != .peso && c != .atencion { one.setVisible(c, false) }
    #expect(one.rows.map { $0.map(\.rawValue) } == [["atencion"], ["peso"]])
    #expect(HomeLayout.standard.items.count == HomeCard.allCases.count && HomeCard.allCases.count == 15)
}

// MARK: - Exportar

@Test func csvQuoting() {
    #expect(CSV.row(["a", "b,c", "d\"e", "f\ng"]) == "a,\"b,c\",\"d\"\"e\",\"f\ng\"")
    #expect(CSV.file(["x", "y"], [["1", "2"]]) == "x,y\n1,2\n")
    #expect(CSV.row(["a\r\nb"]) == "\"a\r\nb\"")
    #expect(Edit.rowString(["a\r\nb", "c\rd", "e\nf|g"]) == "| a b | c d | e f\\|g |")
    #expect(Edit.taskLine("llamar\r\n## Otra sección", due: nil) == "- [ ] llamar ## Otra sección")
    #expect(CSV.num(106.0) == "106" && CSV.num(nil) == "" && CSV.num(7.5) == "7.5")
}

@MainActor @Test func exportsOnCopy() throws {
    guard let path = ProcessInfo.processInfo.environment["VAULT_COPY"] else { return }
    let store = Store(root: try tempVaultCopy(path))
    store.setDiaryValue(DayKey.date("2026-03-05")!, "sueno_h", 7)
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
    let files = try store.exportData(to: out)
    let names = Set(files.map(\.lastPathComponent))
    #expect(names.isSuperset(of: ["peso.csv", "medicacion.csv", "habitos.csv", "tareas.csv", "sueno.csv", "resumen.md"]))
    let peso = try String(contentsOf: out.appendingPathComponent("peso.csv"), encoding: .utf8)
    #expect(peso.hasPrefix("fecha,peso_kg,notas\n") && peso.components(separatedBy: "\n").count > 2)
    let dosis = try String(contentsOf: out.appendingPathComponent("medicacion.csv"), encoding: .utf8)
    #expect(dosis.hasPrefix("fecha,medicamento,dosis,") && dosis.components(separatedBy: "\n").count > 2)
    #expect(try String(contentsOf: out.appendingPathComponent("sueno.csv"), encoding: .utf8).contains("2026-03-05,7"))
    #expect(try String(contentsOf: out.appendingPathComponent("habitos.csv"), encoding: .utf8).components(separatedBy: "\n").count > 2)

    let stats = store.yearStats(2026)
    print("YEAR", stats.firstKg ?? 0, stats.lastKg ?? 0, stats.deltaKg ?? 0, stats.injections, stats.dosesByMg.map { "\($0.mg)x\($0.count)" }, stats.habitByMonth.map { "\($0.month):\(Int($0.pct))" }, stats.tasksDone)
    #expect(stats.firstKg != nil && stats.injections > 0 && !stats.dosesByMg.isEmpty)
    #expect(store.yearStats(2020).weights.isEmpty && store.yearStats(2020).injections == 0)

    let zip = FileManager.default.temporaryDirectory.appendingPathComponent("notas-\(UUID().uuidString).zip")
    #expect(store.exportNotesZip(to: zip) && ((try? FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? Int) ?? 0) > 1000)

    let pdf = FileManager.default.temporaryDirectory.appendingPathComponent("resumen-\(UUID().uuidString).pdf")
    PDFExport.write(YearSummaryView(stats: stats, vaultName: store.vaultName), to: pdf)
    let data = try Data(contentsOf: pdf)
    #expect(data.count > 2000 && String(decoding: data.prefix(5), as: UTF8.self) == "%PDF-")
}

@MainActor @Test func sampleTemplatesAreUsable() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("plantillas-\(UUID().uuidString)")
    let store = Store(root: tmp.appendingPathComponent("V"), backups: tmp.appendingPathComponent("C"))
    store.setUp(modules: [], templates: true)
    #expect(store.userTemplates() == SampleTemplates.names.sorted())
    for name in SampleTemplates.names {
        let answers = Dictionary(uniqueKeysWithValues: store.templateQuestions(name).map { ($0.label, "X") })
        let t = try #require(store.userTemplate(name, title: "Prueba", answers: answers), "\(name)")
        #expect(!t.body.contains("{{") && !t.body.contains("plantilla_carpeta") && t.body.contains("# Prueba"), "\(name)")
        #expect(!MD.frontmatter(t.body).isEmpty, "\(name)")
        // las gráficas apuntan a una tabla que existe en la propia plantilla
        for case .chart(let spec) in MDParser.blocks(t.body) {
            if case .failure(let p) = NoteChart.data(NoteChart.spec(spec), tables: Parse.tables(t.body)) {
                #expect(p.message.hasPrefix("Todavía no hay números"), "\(name): \(p.message)")
            }
        }
    }
    #expect(store.templateQuestions("Viaje").map(\.label) == ["Destino", "Fecha de salida (AAAA-MM-DD)", "Fecha de vuelta (AAAA-MM-DD)"])
    #expect(store.userTemplate("Receta", title: "Lentejas")?.body.contains("**Raciones:** 2") == true)   // valor por defecto
    // no pisa una plantilla propia con el mismo nombre
    try "mía".write(to: store.url("Plantillas/Idea.md"), atomically: true, encoding: .utf8)
    store.createSampleTemplates()
    #expect(store.read("Plantillas/Idea.md") == "mía")
}
