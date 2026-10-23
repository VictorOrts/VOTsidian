import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Rendimiento con muchas notas

@MainActor @Test func bigVaultStaysFast() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("big-\(UUID().uuidString)")
    let vault = tmp.appendingPathComponent("Notas")
    let fm = FileManager.default
    try fm.createDirectory(at: vault.appendingPathComponent(VaultPath.folder("peso")), withIntermediateDirectories: true)
    try "---\nobjetivo_peso_kg: 85\npeso_inicial_kg: 120\n---\n| Fecha | Peso |\n|--|--|\n| 01/01/2026 | 100 |\n".write(to: vault.appendingPathComponent(VaultPath.peso), atomically: true, encoding: .utf8)
    for f in 0..<30 {
        let dir = vault.appendingPathComponent("Carpeta \(f)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for n in 0..<50 {
            let body = "---\ntipo: nota\ntags:\n  - t\(n % 7)\n---\n# Nota \(f)-\(n)\n\nTexto largo de ejemplo con palabras. " + String(repeating: "lorem ipsum dolor sit amet ", count: 60)
                + "\n- [ ] Tarea \(f)-\(n) 📅 2026-12-\(String(format: "%02d", n % 28 + 1))\nVer [[Nota \(f)-\((n + 1) % 50)]] y [[Peso]] #etiqueta\n"
            try body.write(to: dir.appendingPathComponent("Nota \(f)-\(n).md"), atomically: true, encoding: .utf8)
        }
    }
    let clock = ContinuousClock()
    var made: Store?
    let cold = clock.measure { made = Store(root: vault, backups: tmp.appendingPathComponent("Copias")) }   // primera carga: lee y analiza todo
    let store = try #require(made)
    let warm = clock.measure { store.reload() }
    print("PERF notas \(store.notes.count) frío \(cold) caliente \(warm)")
    #expect(store.notes.count == 1501 && store.tasks.count == 1500)
    #expect(warm < .seconds(1.0))
    #expect(warm < cold)                         // la caché evita volver a leer y analizar
    // una edición se ve al instante aunque la caché esté activa
    let editTime = clock.measure { store.edit("Carpeta 0/Nota 0-0.md") { $0 + "\n- [ ] Añadida ahora\n" } }
    let editAgain = clock.measure { store.edit("Carpeta 0/Nota 0-1.md") { $0 + "\n- [ ] Otra\n" } }   // la primera incluye la copia de seguridad del día
    print("PERF edición \(editTime) siguiente \(editAgain)")
    #expect(store.tasks.contains { $0.text == "Añadida ahora" })
    // la recarga incremental deja el mismo estado que una recarga completa desde cero
    let fresh = Store(root: vault, backups: tmp.appendingPathComponent("Copias2"))
    #expect(store.tasks == fresh.tasks && store.notes.map(\.path) == fresh.notes.map(\.path))
    #expect(store.noteMeta == fresh.noteMeta && store.noteTags == fresh.noteTags && store.snippets == fresh.snippets)
    #expect(store.outLinks == fresh.outLinks && store.backLinks == fresh.backLinks && store.aliasIndex == fresh.aliasIndex)
    func paint<V: View>(_ name: String, _ view: V) {
        let t = clock.measure { let r = ImageRenderer(content: view.environment(store).frame(width: 1000, height: 800)); r.scale = 1; _ = r.cgImage }
        print("PERF pantalla \(name) \(t)")
    }
    paint("Inicio", InicioView(go: { _ in }))
    paint("Tareas", TareasView())
    paint("Calendario", CalendarioView())
    paint("Notas", NotasView())
    paint("Semana", SemanaView())
    paint("Proyectos", ProyectosView())
    let edgePairs = (0..<1500).map { ($0, ($0 + 1) % 1500) }
    let layout = clock.measure { _ = GraphLayout.compute(count: 1500, edges: edgePairs) }
    print("PERF grafo disposición \(layout)")
    let agendaCold = clock.measure { _ = store.agenda(from: DayKey.today(), to: DayKey.adding(days: 400, to: DayKey.today())) }
    let agendaHot = clock.measure { _ = store.agenda(from: DayKey.today(), to: DayKey.adding(days: 400, to: DayKey.today())) }
    print("PERF agenda frío \(agendaCold) caliente \(agendaHot)")
    // los enlaces ya están analizados en la caché: no se vuelven a extraer de cada nota
    let broken = clock.measure { _ = store.brokenLinks() }
    print("PERF enlaces rotos \(broken)")
    #expect(broken < .milliseconds(100))
    #expect(agendaHot < agendaCold || agendaHot < .milliseconds(5))
}

// MARK: - Motor de búsqueda

@Test func searchQueryParsing() {
    let today = DayKey.date("2026-10-19")!   // lunes
    let q = SearchQuery.parse("Dieta #Salud carpeta:cambio tipo:plan_nutricional", today: today)
    #expect(q.tokens == ["dieta"] && q.tags == ["salud"] && q.folder == "cambio" && q.type == "plan_nutricional" && q.date == nil)
    let d = SearchQuery.parse("cita el viernes", today: today)
    #expect(d.tokens == ["cita"] && DayKey.string(d.date!) == "2026-10-23")
    #expect(SearchQuery.parse("  ", today: today).isEmpty)
    #expect(SearchQuery.parse("nota: algo", today: today).tokens == ["nota:", "algo"].map { MD.fold($0) })   // «nota:» sin valor no es operador
}

@Test func searchMatchingSynonymsAndHighlight() {
    func m(_ text: String, _ q: String) -> Bool { SearchEngine.matches(MD.fold(text), SearchQuery.parse(q)) }
    #expect(m("El doctor me citó el jueves", "médico"))          // sinónimo
    #expect(m("Pintar techo y reformas", "reforma"))              // plural
    #expect(m("Báscula en ayunas", "peso"))
    #expect(m("Pechuga de pollo y patata", "pollo patata"))       // todas las palabras
    #expect(!m("Pechuga de pollo", "pollo patata"))
    #expect(!m("Algo distinto", "médico"))
    let q = SearchQuery.parse("peso")
    let best = SearchEngine.bestLine(in: "nada\nVer el peso del lunes\nOtra línea con peso y báscula\n", SearchQuery.parse("peso bascula"))
    #expect(best == "Otra línea con peso y báscula")
    let h = SearchEngine.highlight("Peso y peso", q)
    #expect(h.runs.filter { $0.font != nil }.count == 2 && String(h.characters) == "Peso y peso")
    #expect(SearchEngine.passesFilters(path: "a.md", folder: "Salud y deporte", type: "plan", tags: ["salud"], SearchQuery.parse("#sal carpeta:deporte tipo:plan")))
    #expect(!SearchEngine.passesFilters(path: "a.md", folder: "Casa", type: nil, tags: [], SearchQuery.parse("carpeta:deporte")))
}
