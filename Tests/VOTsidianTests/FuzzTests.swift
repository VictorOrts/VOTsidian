import Foundation
import Testing
@testable import VOTsidian

// MARK: - Fuzz: ninguna nota, por rara que sea, debe cerrar la app
//
// Un cierre (índice fuera de rango, `!` sobre nil, `Int(Double)` enorme) mata todo el proceso de tests, así que basta con que
// estas pruebas terminen. La semilla es fija: si alguna falla, falla siempre y se puede reproducir.

private struct Rng: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// `VOT_FUZZ=20 VOT_FUZZ_SEED=3 swift test --filter FuzzTests`: 20 veces más casos y otra semilla, para buscar a fondo.
private let scale = Int(ProcessInfo.processInfo.environment["VOT_FUZZ"] ?? "") ?? 1
private let seed = UInt64(ProcessInfo.processInfo.environment["VOT_FUZZ_SEED"] ?? "") ?? 0

private let fragments: [String] = [
    "---", "---\ntipo: x\nnombre: \"sin cerrar\n", "---\npeso_inicial_kg: abc\nobjetivo_peso_kg: -1\nfecha_inicio: 99/99/9999\n---", "---\nkm: 1e9\nnombre:\nobjetivo_anual: -4\n---",
    "# Título", "## Fechas", "## Mantenimiento", "## Repostajes", "## Servicios", "## Pagos", "## Equipaje", "### Casa", "##", "#", "####### siete", "## Movimientos", "## Partidas", "## Ingresos",
    "| Fecha | Peso (kg) | Notas |", "| Qué | Vence | Notas |", "| Fecha | Km | Qué | Taller | Coste | Cada (km) | Cada (meses) |", "| Servicio | Importe | Cada | Próximo cobro | Partida | Estado |",
    "| Préstamo | Pendiente | Cuota | Día | Hasta |", "| Título | Autor | Estado | Empezado | Terminado | Nota | Páginas |", "| Destino | Salida | Vuelta | Presupuesto | Estado |",
    "| Partida | Previsto | Tipo | Pagado | Día | Cada | Desde |", "| Medicamento | Dosis | Forma | Cada | Horas | Desde | Hasta |", "| Hábito | L | M | X | J | V | S | D | Criterio |",
    "| :--- | :---: | ---: |", "|---|", "| --- |", "| 2026-10-01 | 80 | x |", "| 01/10/2026 | 80,5 |", "| 2026-10-01 | Coche | 500 | |", "|", "||", "| a | b", "a | b |", "| \\| | x |", "| | | |",
    "| 31/02/2026 | 1e999 | |", "| Netflix | 12,99 € | Mensual | 2026-01-15 | | Activa | |", "| Dune | Herbert | Terminado | 2026-01-01 | 2026-01-20 | ⭐⭐⭐ | 600 |", "| Lisboa | 2026-12-01 | 2026-12-05 | 800 € | Reservado | |",
    "| 2026-10-01 | 114.100 | 30 | 47,40 € |", "| 2026-01-10 | 100.000 | Aceite | Taller | 180 € | 15.000 | 12 |", "| Coche | 6.000 € | 500 € | 15 | | Préstamo | |",
    "- [ ] tarea 📅 2026-10-01", "- [x] hecha ✅ 2026-10-01 [completion:: 2026-10-02]", "- [ ] 🔁 every 0 days", "- [ ] ⏫ 📅 9999-99-99", "* [ ] x", "1. [ ] y", "- [ ]", "- [x]x", "- [ ] 📅 2026-02-30", "- [ ] 🔁 every month when done 📅 2026-01-31",
    "```", "```grafica\ntabla: X\ny: A,B\ntipo: tarta\n```", "```dataviewjs\nconst x = '| 1 | 2 |';\n```", "~~~", "> cita", "> [!note] aviso",
    "[[A]]", "![[B#C]]", "![[x.png]]", "[[", "]]", "[[a|b]]", "[[#]]", "[[A]] [[A]] [[A]]", "![[]]", "#etiqueta #otra/sub #123",
    "ñandú ✅ 🎉", "\u{200B}\u{202E}rtl", "e\u{0301}e\u{0301}", String(repeating: "a", count: 5000), String(repeating: "| x ", count: 400) + "|", "     ", "\t\t|\t|", "",
    "| ٢٠٢٦-١٠-٠١ | ٨٠ |", "| ２０２６-１０-０１ | ８０ |", "| २९/१०/२०२६ | 80 |", "- [ ] árabe 📅 ٢٠٢٦-١٠-٠١", "- [ ] mixta 📅 2026-١٠-01 ✅ ２０２６-１０-０２",
    "1.234,56", "-", "∞", "٣", "1/0", "99999999999999999999", "-0", "NaN", "0x10", "1,2,3", "12:60", "25:99",
]

private func randomNote(_ r: inout Rng) -> String {
    let n = Int.random(in: 1...45, using: &r)
    let sep = Bool.random(using: &r) ? "\n" : "\r\n"
    return (0..<n).map { _ in fragments.randomElement(using: &r)! }.joined(separator: sep)
}

/// Una nota de verdad, rota: líneas borradas, repetidas, cambiadas de sitio o cortadas por la mitad.
private func mutate(_ text: String, _ r: inout Rng) -> String {
    var lines = text.components(separatedBy: "\n")
    for _ in 0..<Int.random(in: 1...6, using: &r) where !lines.isEmpty {
        let i = Int.random(in: 0..<lines.count, using: &r)
        switch Int.random(in: 0..<6, using: &r) {
        case 0: lines.remove(at: i)
        case 1: lines.insert(lines[i], at: i)
        case 2: lines.swapAt(i, Int.random(in: 0..<lines.count, using: &r))
        case 3: lines[i] = String(lines[i].prefix(Int.random(in: 0...max(0, lines[i].count), using: &r)))
        case 4: lines.insert(fragments.randomElement(using: &r)!, at: i)
        default: lines[i] = lines[i].replacingOccurrences(of: "|", with: Bool.random(using: &r) ? "" : "||")
        }
    }
    return lines.joined(separator: "\n")
}

/// Pasa el texto por todos los lectores y por lo que se calcula con lo leído.
private func readEverything(_ t: String) {
    _ = (Parse.weight(t), Parse.mascota(t), Parse.tasks(t, file: "x.md"), Parse.week(t, key: "2026-W01"), Parse.plan(t), Parse.milestones(t))
    _ = (Parse.tables(t), Parse.people(t), Parse.listItems(t, section: "Fechas"), Parse.listItems(t, section: ""), Parse.medicationTables(t), Parse.casa(t), Measures.parse(t))
    let med = Parse.medicacion(t)
    _ = (med.main, med.active(), med.pending(), med.daysUntilNext, med.meds.map { (med.next(of: $0), med.daysUntil($0), med.taken($0, on: DayKey.today()), $0.frequencyText) })
    let b = Parse.budget(t, month: "2026-10", path: "x.md")
    _ = (BudgetStatus(b).leftToday, b.spent, b.lines.map { b.real($0) })
    let car = Parse.vehiculo(t)
    _ = (car.nextServices(), car.consumption, car.currentKm, car.spent(year: 2026), car.currentKm.map(Vehiculo.kmText))
    let susc = Parse.suscripciones(t)
    _ = (susc.upcoming(), susc.monthlyTotal, susc.items.map { $0.occurrences(from: DayKey.today(), to: DayKey.adding(days: 900, to: DayKey.today())) })
    let loans = Parse.prestamos(t)
    _ = loans.statuses().map { (loans.dueDates($0, upTo: DayKey.adding(days: 900, to: DayKey.today())), $0.progress, $0.estimatedEnd) }
    let books = Parse.lecturas(t)
    _ = (books.finished(in: 2026), books.pages(in: 2026), books.averageDays, books.projection(), books.goal)
    let tr = Parse.tramites(t)
    _ = (tr.pendingProcedures, tr.yearlyInsurance, tr.insurances.map { ($0.nextRenewal(), $0.renewals(from: DayKey.today(), to: DayKey.adding(days: 900, to: DayKey.today()))) })
    let trips = Parse.viajes(t)
    _ = (trips.upcoming(), trips.trips.map { (trips.spent($0), $0.days, trips.isOngoing($0)) }, trips.packing)
    _ = (Parse.tasks(t, file: "x.md").map(\.text), Shopping.parse(t), Links.extract(t), MDParser.blocks(t), MD.frontmatter(t), MD.frontmatterList(t, key: "aliases"))
    _ = (NoteInfo.tags(t), NoteInfo.snippet(t), NoteInfo.wordCount(t), NoteInfo.aliases(t), Edit.tidyFooter(t), Edit.removeDataview(t))
    let spec = NoteChart.spec(t)
    _ = (NoteChart.data(spec, tables: Parse.tables(t)), NoteChart.kind(t))
    for s in t.components(separatedBy: "\n").prefix(40) { _ = (MDParser.inline(s), DayKey.date(s), DayKey.dmyDate(s), MD.number(s), Money.parse(s), Medication.every(s), Medication.times(s)) }
}

/// Pasa el texto por todos los editores, con líneas y nombres que a veces no existen.
private func editEverything(_ t: String, _ r: inout Rng) {
    let line = Int.random(in: -3...60, using: &r)
    let day = DayKey.today()
    let task = Parse.tasks(t, file: "x.md").first
    _ = Edit.addWeight(t, date: day, kg: 80, note: "n")
    _ = (Edit.addDose(t, date: day, dose: 0.5, site: "Brazo", note: "", med: "X"), Edit.addMascotaVisit(t, date: day, tipo: "Vacuna", detalle: "", proxima: day, coste: "4"))
    _ = (Edit.toggleHabit(t, habit: "Pasos", day: Int.random(in: -2...9, using: &r)), Edit.setValue(t, after: "**Logros:**", value: "x"), Edit.setObjective(t, index: Int.random(in: -1...5, using: &r), value: "x"))
    _ = (Edit.addInboxTask(t, task: "t", due: day, recurrence: "every week", priority: 2), Edit.addRow(t, section: "Fechas", cells: ["a", "b"]), Edit.appendToSection(t, section: "Fechas", line: "- x"))
    _ = (Edit.setSectionCell(t, section: "Fechas", line: line, expectFirst: "ITV", column: "Vence", value: "2026-01-01"), Edit.updateRow(t, line: line, expectFirst: "a", cells: ["x"]))
    _ = (Edit.deleteRow(t, line: line, expectFirst: "a"), Edit.insertTableRow(t, afterLine: line, cells: ["x", "y"]), Edit.toggleCheckbox(t, line: line, expect: "- [ ] x"), Edit.toggleCheckbox(t, line: line))
    _ = (Edit.deleteLine(t, raw: "- [ ] x", hint: line), Edit.setFrontmatter(t, key: "k", value: "v"), Edit.setFrontmatterList(t, key: "aliases", items: ["a", "b"]))
    _ = (Edit.renameLinks(t, old: "A", new: "B"), Edit.unlink(t, name: "A"), Edit.addRelated(t, links: ["A"]), Edit.linkMention(t, name: "A"), Edit.appendToSectionCreating(t, section: "Fechas", lines: ["x"]))
    _ = (Edit.addHabitRow(t, name: "H"), Edit.removeHabitRow(t, name: "H"), Edit.setHabitTable(t, defs: [HabitDef(name: "A", criterion: "b")]))
    _ = (Edit.addBudgetIncome(t, name: "x"), Edit.addBudgetLine(t, name: "x", amount: 5, kind: .fijo, every: 1, start: nil), Edit.addBudgetMove(t, date: day, amount: 3, category: "A", note: "n"))
    _ = (Edit.normalizeBudgetTable(t, section: "Partidas"), Edit.renameBudgetLine(t, line: line, from: "A", to: "B"))
    _ = (Edit.addVehiculoRow(t, section: "Repostajes", cells: ["x"]), Edit.setRowValues(t, line: line, expectFirst: "a", values: ["estado": "x"]), Edit.uncheckSection(t, section: "Equipaje"))
    _ = (Edit.addSuscripcion(t, name: "N", amount: 1, every: "Mensual", date: day, category: "", trial: false), Edit.addPrestamo(t, name: "P", initial: 5, installment: 1, day: 3, until: nil, category: ""))
    _ = (Edit.addPrestamoPago(t, date: day, loan: "P", amount: 1, note: ""), Edit.addLibro(t, title: "L", author: "A", pages: 3), Edit.addViaje(t, name: "V", start: day, end: day, budget: 1), Edit.addViajeGasto(t, date: day, trip: "V", concept: "c", amount: 1))
    _ = (Edit.addTramite(t, name: "T", due: day, every: "Anual", amount: 3), Edit.addSeguro(t, name: "S", company: "C", premium: 3, every: "Anual", renewal: day, phone: "", category: ""))
    _ = (Edit.addMedication(t, Medication(name: "X", dose: "1 mg", form: "Pastilla", every: 1), current: nil), Edit.upgradeMedicationNote(t, current: Medication(name: "X", dose: "", form: "", every: 7)))
    if let task {
        _ = (Edit.setTask(t, task: task, done: true), Edit.completeRecurring(t, task: task), Edit.updateTask(t, task: task, newText: "z", due: day, priority: 1))
    }
}

@Test func randomNotesNeverCrash() {
    var r = Rng(state: 20_261_024 &+ seed)
    for _ in 0..<(500 * scale) {
        let t = randomNote(&r)
        readEverything(t)
        editEverything(t, &r)
    }
}

@MainActor @Test func mutatedRealNotesNeverCrash() throws {
    var r = Rng(state: 7_777 &+ seed)
    let notes = [pesoFixture, medicacionFixture, casaFixture, weekFixture, vehiculoFixture, suscripcionesFixture, prestamosFixture, lecturasFixture, viajesFixture,
                 gastosFixture(Date(), full: true)] + SampleTemplates.names.compactMap { _ in nil as String? }
    for note in notes {
        readEverything(note)
        for _ in 0..<(120 * scale) {
            let t = mutate(note, &r)
            readEverything(t)
            editEverything(t, &r)
        }
    }
}

@Test func randomLinesNeverCrashTheLineParsers() {
    var r = Rng(state: 99 &+ seed)
    let words = ["peso", "animo", "dormi", "gasto", "cuota", "libro", "tarea", "cita", "compra", "pinchazo", "cintura", "devolucion", "termine", "hoy", "mañana", "ayer", "el viernes", "el 29/10", "cada mes",
                 "cada 2 semanas", "25/11", "2026-02-30", "99999999999999999999", "el ٢٩", "en ٣ días", "٢٢ € cena", "２９/１０", "1,5", "-3", "€", "22 € cena con Ana", "0,0", "NaN", "inf", "⏫", "🔁", "📅", "#etiqueta", "carpeta:casa", "tipo:evento", "[[", "]]", "\u{202E}"]
    for _ in 0..<(4000 * scale) {
        let s = (0..<Int.random(in: 1...7, using: &r)).map { _ in words.randomElement(using: &r)! }.joined(separator: Bool.random(using: &r) ? " " : "")
        _ = (QuickCommand.parse(s), NaturalDate.extract(s), NaturalDate.extractTask(s), ExpenseParser.parse(s, categories: ["Alimentación", "Transporte"], people: ["Ana"], learned: ["cena": "Alimentación"]))
        let q = SearchQuery.parse(s)
        _ = (q, SearchEngine.matches(MD.fold(s), q), SearchEngine.bestLine(in: s, q), SearchEngine.highlight(s, q), SuscripcionesData.Period.parse(s), CalendarEventSpec.Recurrence.parse(s), CalendarEventSpec.seconds(s), Recurrence.describe(s), Money.parse(s), MD.number(s), Vehiculo.km(s))
        _ = (MD.fold(s), MD.cells(s), MD.rawCells(s), MD.escapeCell(s), DayKey.date(s), DayKey.dmyDate(s), Medication.every(s), Medication.times(s))
    }
}

// MARK: Regresiones de lo que encontró el fuzz

@Test func naturalDatesSurviveTextWhoseFoldingChangesLength() throws {
    let today = try #require(DayKey.date("2026-10-23"))
    let tomorrow = DayKey.adding(days: 1, to: today)
    // «ñ» descompuesta (n + tilde suelta), como al pegar desde un PDF
    #expect(NaturalDate.extract("pagar man\u{0303}ana", today: today).date == tomorrow && NaturalDate.extract("pagar man\u{0303}ana", today: today).text == "pagar")
    // banderas, emojis compuestos y ß delante de la fecha: las posiciones siguen cuadrando
    for prefix in ["🇪🇸", "👨‍👩‍👧", "🧑🏽‍💻", "straße", "ﬁnanzas", "e\u{0301}\u{0301}"] {
        let r = NaturalDate.extract("\(prefix) mañana", today: today)
        #expect(r.date == tomorrow && r.text.hasPrefix(prefix.precomposedStringWithCanonicalMapping) && !r.text.contains("ñana"), "\(prefix)")
        #expect(NaturalDate.extract("llamar \(prefix) el 29/10", today: today).date == DayKey.date("2026-10-29"))
        #expect(NaturalDate.extractTask("regar \(prefix) cada semana", today: today).recurrence != nil)
        #expect(ExpenseParser.parse("22 € cena \(prefix) ayer", categories: ["Alimentación"], today: today)?.amount == 22)
    }
    #expect(NaturalDate.aligned("a🇪🇸B").utf16.count == "a🇪🇸B".utf16.count && NaturalDate.aligned("Ñandú").utf16.count == 5 && NaturalDate.aligned("Ñandú") == "nandu")
}

@Test func editsWithStaleOrNegativeLinesDoNothingInsteadOfCrashing() {
    let note = "| Partida | Previsto |\n| --- | --- |\n| Comida | 100 |\n\n## Movimientos\n\n| Fecha | Importe | Partida | Nota |\n| --- | --- | --- | --- |\n"
    #expect(Edit.renameBudgetLine(note, line: -1, from: "Comida", to: "X") == nil && Edit.renameBudgetLine(note, line: 999, from: "Comida", to: "X") == nil)
    #expect(Edit.toggleHabit("| Hábito | L | M |\n| --- | --- | --- |\n| Pasos | | |", habit: "Pasos", day: -1) == nil)
    #expect(Edit.setRowValues(note, line: -5, expectFirst: "a", values: ["x": "y"]) == nil && Edit.updateRow(note, line: -2, expectFirst: "a", cells: ["b"]) == nil)
    #expect(Edit.deleteRow(note, line: 500, expectFirst: "a") == nil && Edit.toggleCheckbox("- [ ] a", line: -9) == nil)
    // un registro que es solo la cabecera, al final del archivo, acepta la primera fila
    let header = "## Registro\n\n| Fecha | Medicamento | Dosis | Zona | Notas |"
    #expect(Edit.addIntake(header, date: DayKey.today(), med: "X", dose: "1 mg", site: "", note: "", replaceSameDay: false)?.contains("1 mg") == true)
    var lines = ["a"]
    lines.insertClamped("b", at: 99); lines.insertClamped("c", at: -4); lines.insertClamped(contentsOf: ["d", "e"], at: 99)
    #expect(lines == ["c", "a", "b", "d", "e"])
}

// MARK: Una carpeta de notas hostil

@MainActor @Test func hostileVaultNeverBreaksTheStore() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("hostil-\(UUID().uuidString)/V")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    func write(_ rel: String, _ data: Data) throws {
        let u = dir.appendingPathComponent(rel)
        try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: u)
    }
    try write("Notas/Buena.md", Data("# Buena\nver [[Rota]] y [[Buena]]\n- [ ] tarea 📅 \(isoDay(1))\n".utf8))
    try write("Notas/Invalida.md", Data([0xFF, 0xFE, 0x00, 0xC3, 0x28, 0xA0, 0xA1, 0x23, 0x20, 0x68]))         // UTF-8 inválido
    try write("Notas/Bom.md", Data([0xEF, 0xBB, 0xBF]) + Data("---\ntipo: evento\nfecha_evento: \(isoDay(5))\n---\n# Con BOM\n".utf8))
    try write("Notas/Vacia.md", Data())
    try write("Notas/Enorme.md", Data(repeating: UInt8(ascii: "a"), count: 3_000_000) + Data("\n- [ ] al final\n".utf8))   // una línea de 3 MB
    try write("Notas/Windows.md", Data("# Win\r\n- [ ] crlf 📅 \(isoDay(2))\r\n| a | b |\r\n| - | - |\r\n".utf8))
    try write("Notas/ñandú 🇪🇸 e\u{0301}.md", Data("# Raro\n".utf8))
    try write("Notas/con\nsalto.md", Data("# Salto\n".utf8))
    try write("Notas/Nota 2.md", Data("# copia de conflicto\n".utf8))
    try write("Notas/.Oculta.md.icloud", Data("marcador".utf8))
    try write(".DS_Store", Data([0, 1, 2]))
    try write("Notas/sin-extension", Data("no es una nota".utf8))
    try write("Notas/foto.png", Data([0x89, 0x50, 0x4E, 0x47]))
    try fm.createDirectory(at: dir.appendingPathComponent("Notas/directorio.md"), withIntermediateDirectories: true)   // una carpeta que parece una nota
    try? fm.createSymbolicLink(at: dir.appendingPathComponent("Notas/bucle"), withDestinationURL: dir)                 // un enlace a sí misma
    try? fm.createSymbolicLink(at: dir.appendingPathComponent("Notas/roto.md"), withDestinationURL: dir.appendingPathComponent("no-existe.md"))
    var deep = "Hondo"
    for i in 0..<40 { deep += "/n\(i)" }
    try write("\(deep)/Fondo.md", Data("# Fondo\n".utf8))
    try write("Salud/Peso.md", Data("---\npeso_inicial_kg: abc\n---\n| Fecha | Peso (kg) |\n| - | - |\n| 99/99/9999 | x |\n| 01/10/2026 | 80 |\n".utf8))

    let store = Store(root: dir)
    let titles = Set(store.notes.map(\.name))
    #expect(titles.isSuperset(of: ["Buena", "Bom", "Vacia", "Enorme", "Windows", "Fondo", "Peso"]))
    #expect(store.tasks.contains { $0.text == "tarea" } && store.tasks.contains { $0.text == "crlf" })
    #expect(store.weight.records.count == 1)
    // todo lo que se calcula con lo leído aguanta
    _ = (store.alerts(), store.sidebarCounts(), store.brokenLinks(), store.agenda(from: DayKey.today(), to: DayKey.adding(days: 30, to: DayKey.today())), store.conflictCopies)
    _ = store.notes.map { (store.read($0.path).count, store.noteMeta[$0.path], store.outLinks[$0.path], store.backLinks[$0.path]) }
    let q = SearchQuery.parse("buena rota")
    _ = store.notes.filter { SearchEngine.matches(MD.fold(store.read($0.path)), q) }
    // escribir, copiar toda la carpeta y exportar tampoco se rompe
    #expect(store.edit("Notas/Buena.md") { $0 + "\nmás\n" })
    let out = fm.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
    #expect(!(try store.exportData(to: out)).isEmpty)
    store.reload()
    #expect(store.notes.contains { $0.name == "Buena" })
}

// MARK: Deshacer devuelve la carpeta exactamente como estaba

/// Todos los archivos de la carpeta con su contenido (sin las carpetas vacías, que no cuentan).
private func snapshot(_ root: URL) throws -> [String: Data] {
    var out: [String: Data] = [:]
    let base = root.resolvingSymlinksInPath().path
    for case let u as URL in FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])! {
        guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
        out[String(u.resolvingSymlinksInPath().path.dropFirst(base.count + 1))] = try Data(contentsOf: u)
    }
    return out
}

@MainActor @Test func everyOperationIsUndoneExactly() throws {
    let day = DayKey.today()
    let operations: [(String, (Store) -> Void)] = [
        ("peso", { $0.addWeight(date: day, kg: 79.5, note: "x") }),
        ("pinchazo", { $0.injectToday() }),
        ("dosis", { $0.addDose(date: day, dose: 0.5, site: "Brazo", note: "") }),
        ("mascota", { $0.addMascotaVisit(date: day, tipo: "Vacuna", detalle: "", proxima: nil, coste: "") }),
        ("tarea", { $0.addTask("nueva", due: day, recurrence: "every week", priority: 2) }),
        ("completar", { s in if let t = s.tasks.first(where: { $0.text == "previa" }) { s.setTask(t, done: true) } }),
        ("idea", { $0.addIdea("una idea") }),
        ("diario", { $0.appendToDiary(day, text: "hoy") }),
        ("ánimo", { $0.setDiaryValue(day, "animo", 4) }),
        ("gasto", { $0.addExpense(12, category: "Alimentación", note: "pan", date: day) }),
        ("compra", { _ = $0.addShopping(["leche", "pan"]) }),
        ("repostaje con gasto", { $0.addRepostaje(date: day, km: 115_000, liters: 30, amount: 45, expense: true) }),
        ("taller con gasto", { $0.addMantenimiento(date: day, km: nil, what: "Ruedas", shop: "", cost: 200, everyKm: nil, everyMonths: nil, expense: true) }),
        ("suscripción", { $0.addSuscripcion(name: "Nueva", amount: 5, every: "Mensual", date: day, category: "", trial: false) }),
        ("estado suscripción", { s in if let i = s.suscripciones.items.first { s.setSuscripcionStatus(i, to: "Cancelada") } }),
        ("cobro suscripción", { s in if let i = s.suscripciones.items.first { s.logSuscripcionCharge(i) } }),
        ("préstamo", { $0.addPrestamo(name: "Nuevo", initial: 900, installment: 100, day: 3, until: nil, category: "") }),
        ("cuota con gasto", { s in if let l = s.prestamos.loans.first { s.addPrestamoPago(l, amount: 500, expense: true) } }),
        ("libro", { $0.addLibro(title: "Nuevo", author: "A", pages: 10) }),
        ("empezar libro", { s in if let b = s.lecturas.pending.first { s.startBook(b) } }),
        ("terminar libro", { s in if let b = s.lecturas.reading.first { s.finishBook(b, rating: 4) } }),
        ("viaje", { $0.addViaje(name: "Roma", start: day, end: day, budget: 500) }),
        ("gasto de viaje con gasto", { s in if let t = s.viajes.trips.first { s.addViajeGasto(t, concept: "Cena", amount: 30, expense: true) } }),
        ("equipaje", { $0.addPacking("Paraguas") }),
        ("marcar equipaje", { s in if let p = s.viajes.packing.first { s.togglePacking(p) } }),
        ("orden libro", { $0.run(.book("Orden", "")) }),
        ("orden cuota", { $0.run(.loanPayment("Coche")) }),
        ("orden gasto", { $0.run(.expense(ExpenseParser.Result(amount: 9, category: "Alimentación", note: "x", person: nil, date: day))) }),
        ("trámite hecho con gasto", { s in if let p = s.tramites.procedures.first(where: { $0.name == "Basuras" }) { s.markTramiteDone(p, expense: true) } }),
        ("pago de seguro", { s in if let i = s.tramites.insurances.first { s.logSeguroPayment(i) } }),
        ("trámite nuevo", { $0.addTramite(name: "Tasa", due: day, every: "Anual", amount: 30) }),
        ("seguro nuevo", { $0.addSeguro(name: "Coche", company: "X", premium: 400, every: "Anual", renewal: day, phone: "1", category: "") }),
        ("nota nueva", { _ = $0.createNote(folder: "Casa", name: "Probando", template: "En blanco") }),
        ("propiedad", { $0.setProperty(VaultPath.peso, key: "objetivo_peso_kg", value: "70") }),
    ]
    for (name, op) in operations {
        let root = try syntheticVault()
        try "- [ ] previa 📅 \(isoDay(1))\n".write(to: root.appendingPathComponent("Notas/Previa.md"), atomically: true, encoding: .utf8)
        let store = Store(root: root)
        let before = try snapshot(store.root)
        let steps = store.undoStack.count
        op(store)
        let after = try snapshot(store.root)
        let made = store.undoStack.count - steps
        #expect(after != before, "«\(name)» no cambió nada")
        #expect(made >= 1 && made <= 3 && store.canUndo, "«\(name)» dejó \(made) pasos de deshacer")
        // Una operación puede dejar más de un paso (la nota de arranque que crea y luego su primer apunte): se deshacen todos.
        for _ in 0..<made { store.undo() }
        let restored = try snapshot(store.root)
        let differences = Set(restored.keys).symmetricDifference(before.keys).sorted() + restored.keys.filter { before[$0] != nil && before[$0] != restored[$0] }.sorted()
        #expect(restored == before, "deshacer «\(name)» no devolvió la carpeta a como estaba: \(differences)")
        // y repetirla desde ahí da lo mismo que la primera vez
        op(store)
        let again = try snapshot(store.root)
        let stable = again == after || ["diario", "ánimo", "completar"].contains(name)   // llevan la hora o la fecha de hoy dentro
        #expect(stable, "repetir «\(name)» da otro resultado: \(Set(again.keys).symmetricDifference(after.keys).sorted() + again.keys.filter { after[$0] != nil && after[$0] != again[$0] }.sorted())")
    }
}

@Test func datesIgnoreDigitsFromOtherAlphabetsAndHugeOffsets() throws {
    for text in ["٢٠٢٦-١٠-٠١", "２０２６-１０-０１", "2026-١٠-01", "२०२६-१०-०१"] { #expect(DayKey.date(text) == nil, "\(text)") }
    for text in ["٢٩/١٠/٢٠٢٦", "２９/１０/２０２６", "29/١٠/2026"] { #expect(DayKey.dmyDate(text) == nil, "\(text)") }
    #expect(DayKey.date("2026-10-23") != nil && DayKey.dmyDate("23/10/2026") != nil)
    let today = DayKey.today()
    for text in ["llamar el ٢٩", "pagar en ٣ días", "cita ２９/１０", "tarea 2026-١٠-01", "revisar el ٣١ de octubre"] {
        _ = (NaturalDate.extract(text, today: today), NaturalDate.extractTask(text, today: today))
    }
    #expect(NaturalDate.extract("llamar el ٢٩", today: today).date == nil && NaturalDate.extract("pagar en 3 días", today: today).date == DayKey.adding(days: 3, to: today))
    // un número de días absurdo no cierra la app
    for days in [Int.max, Int.min, 1_000_000_000_000, -1_000_000_000_000, 0] { _ = DayKey.adding(days: days, to: today) }
    #expect(DayKey.adding(days: 5, to: today) == DayKey.calendar().date(byAdding: .day, value: 5, to: today))
}

// MARK: Todas las pantallas con notas rotas

@MainActor @Test func everyScreenRendersWithBrokenNotes() throws {
    let fixtures: [String: String] = [
        VaultPath.peso: pesoFixture, VaultPath.medicacion: medicacionFixture, VaultPath.casa: casaFixture, VaultPath.vehiculo: vehiculoFixture,
        VaultPath.suscripciones: suscripcionesFixture, VaultPath.prestamos: prestamosFixture, VaultPath.lecturas: lecturasFixture, VaultPath.viajes: viajesFixture,
        "\(VaultPath.revisiones)/\(DayKey.weekKey(Date())).md": weekFixture, "Finanzas/Gastos/\(Budget.monthKey(Date())).md": gastosFixture(Date()),
    ]
    let others = [VaultPath.plan, VaultPath.medico, VaultPath.finanzas, VaultPath.compra, VaultPath.moda, VaultPath.mascota, VaultPath.personas, VaultPath.documentos, VaultPath.objetivos,
                  VaultPath.inbox, VaultPath.medidas, VaultPath.proyecto, "Diario/\(DayKey.string(DayKey.today())).md"]
    for round in 0..<6 {
        var r = Rng(state: 31_337 &+ UInt64(round) &+ seed)
        var files: [String: String] = [:]
        for (rel, text) in fixtures { files[rel] = round == 0 ? text : mutate(mutate(text, &r), &r) }
        for rel in others { files[rel] = randomNote(&r) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rotas-\(UUID().uuidString)/V")
        for (rel, text) in files {
            let u = dir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: u, atomically: true, encoding: .utf8)
        }
        let store = Store(root: dir)
        store.createSampleTemplates()
        try renderAllScreens(store)
        _ = (store.alerts(), store.sidebarCounts(), store.agenda(from: DayKey.today(), to: DayKey.adding(days: 60, to: DayKey.today())), store.reminderSources())
        _ = ICS.events(store.reminderSources(), plan: ReminderPlan()).map(CalendarEventSpec.init)
    }
}

// MARK: El lector de números rápido da lo mismo que el de antes

/// `MD.number` tal como era, con expresión regular (solo cifras ASCII, como ahora).
private func referenceNumber(_ s: String) -> Double? {
    guard let m = s.firstMatch(of: /-?[0-9]+(?:[.,][0-9]+)*/) else { return nil }
    var t = String(m.0)
    let commas = t.filter { $0 == "," }.count, dots = t.filter { $0 == "." }.count
    if commas > 0, dots > 0 {
        let decimal: Character = t.lastIndex(of: ",")! > t.lastIndex(of: ".")! ? "," : "."
        t = t.filter { $0 != (decimal == "," ? "." : ",") }.replacingOccurrences(of: ",", with: ".")
    } else if dots > 1 || commas > 1 {
        t = t.replacingOccurrences(of: dots > 1 ? "." : ",", with: "")
    } else {
        t = t.replacingOccurrences(of: ",", with: ".")
    }
    return Double(t)
}

@Test func fastNumberParserMatchesTheOldOne() {
    var r = Rng(state: 4242 &+ seed)
    let pieces = ["1", "23", "456", "7.890", "1,5", ".", ",", "-", "--", " ", "€", "kg", "a", "1.234,56", "1,234.56", "1.2.3", "1,,2", "..5", "5..", "-0", "ñ", "٣", "１", "e", "+", "0", "00", "%"]
    for _ in 0..<(20_000 * scale) {
        let s = (0..<Int.random(in: 0...6, using: &r)).map { _ in pieces.randomElement(using: &r)! }.joined()
        #expect(MD.number(s) == referenceNumber(s), "«\(s)»: \(String(describing: MD.number(s))) frente a \(String(describing: referenceNumber(s)))")
    }
    for s in ["105,5", "1.234,5", "1.234.567", "1,234.5", "-3", "a-5", "5-3", "12,99 €", "", "abc", "1e5"] { #expect(MD.number(s) == referenceNumber(s), "\(s)") }
}
