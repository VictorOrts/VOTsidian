import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

@Test func parsesWeightIgnoringCodeBlocks() {
    let w = Parse.weight(pesoFixture)
    #expect(w.records.count == 2)
    #expect(w.last?.kg == 106)
    #expect(w.goalKg == 90 && w.initialKg == 136)
    #expect(abs(w.progress - 30.0 / 46.0) < 0.001)
}

@Test func addWeightInsertsAfterLastDatedRow() throws {
    let out = try #require(Edit.addWeight(pesoFixture, date: DayKey.date("2026-10-31")!, kg: 104.5, note: "ok"))
    let w = Parse.weight(out)
    #expect(w.records.count == 3 && w.last?.kg == 104.5)
    #expect(out.contains("| 31/10/2026 | 104.5 | ok |\n|            |"))
    // mismo día reemplaza
    let again = try #require(Edit.addWeight(out, date: DayKey.date("2026-10-31")!, kg: 104.0, note: ""))
    #expect(Parse.weight(again).records.count == 3)
}

@Test func mounjaroNextAndSite() throws {
    let m = Parse.mounjaro(mounjaroFixture)
    #expect(m.doses.count == 2)
    #expect(DayKey.string(m.next!) == "2026-10-18")
    #expect(m.suggestedSite == "Abdomen derecho")
    let out = try #require(Edit.addDose(mounjaroFixture, date: DayKey.date("2026-10-19")!, dose: 7.5, site: "Abdomen derecho", note: ""))
    #expect(out.contains("| 2026-10-19 | 7,5 mg | Abdomen derecho |  |"))
    #expect(Parse.mounjaro(out).doses.count == 3)
}

@Test func weekParseAndEdits() throws {
    let r = Parse.week(weekFixture, key: "2026-W43")
    #expect(r.habits.map(\.name) == ["Proteína", "Pasos"])
    #expect(r.habits[0].count == 1)
    #expect(r.logros == "Todo bien" && r.objetivos == ["Uno", "", ""])
    #expect(r.fechas == ["Dentista el martes"])

    let toggled = try #require(Edit.toggleHabit(weekFixture, habit: "pasos", day: 2))
    #expect(Parse.week(toggled, key: "k").habits[1].days[2])
    // alinea y no rompe otras celdas
    #expect(Parse.week(toggled, key: "k").habits[0].count == 1)
    let off = try #require(Edit.toggleHabit(toggled, habit: "Pasos", day: 2))
    #expect(Parse.week(off, key: "k").habits[1].count == 0)

    var t = try #require(Edit.setValue(weekFixture, after: "**Lo que no salió:**", value: "Ahorro"))
    t = try #require(Edit.setObjective(t, index: 1, value: "Dos"))
    t = try #require(Edit.setDates(t, items: ["Cita A", "- [ ] Cita B"]))
    let p = Parse.week(t, key: "k")
    #expect(p.noSalio == "Ahorro" && p.objetivos == ["Uno", "Dos", ""] && p.fechas == ["Cita A", "[ ] Cita B"])
    #expect(t.hasSuffix("---"))
}

@Test func tasksParseAndToggle() throws {
    let text = "# x\n- [ ] Cita dentista 📅 2026-10-20\n- [x] Hecha [completion:: 2026-10-10]\n- [ ] \n- [ ] Sin fecha\n```\n- [ ] en código\n```"
    let tasks = Parse.tasks(text, file: "a/Nota.md")
    #expect(tasks.count == 3)
    #expect(tasks[0].text == "Cita dentista" && DayKey.string(tasks[0].due!) == "2026-10-20")
    #expect(tasks[1].done && tasks[1].text == "Hecha")
    let done = try #require(Edit.setTask(text, task: tasks[0], done: true, on: DayKey.date("2026-10-19")!))
    #expect(done.contains("- [x] Cita dentista 📅 2026-10-20 [completion:: 2026-10-19]"))
    let back = try #require(Edit.setTask(done, task: Parse.tasks(done, file: "a").first!, done: false))
    #expect(back == text)
}

@Test func inboxTaskGoesToSection() throws {
    let inbox = "# Inbox\n## Pendiente de clasificar\n- [x] Vieja\n- [ ] Idea\n\n## Ideas\n- \n"
    let out = try #require(Edit.addInboxTask(inbox, task: "Llamar", due: DayKey.date("2026-11-02")))
    #expect(out.contains("- [ ] Idea\n- [ ] Llamar 📅 2026-11-02\n\n## Ideas"))
}

@Test func nalaAlerts() {
    let text = "---\nnombre: Nala\nnacimiento: 01/04/2022\n---\n## Salud\n| Fecha | Tipo | Detalle | Próxima | Coste |\n| --- | --- | --- | --- | --- |\n| 2024-02-16 | Revisión | | 2024-12-01 | |\n| 2026-01-01 | Vacuna | | 2099-01-01 | |"
    let n = Parse.nala(text)
    #expect(n.visits.count == 2)
    #expect(n.overdue.count == 1 && n.overdue[0].title == "Revisión")
    #expect(n.upcoming.count == 1)
}

@Test func weekTemplateRoundTrips() {
    let t = Template.week(key: "2026-W44", monday: DayKey.date("2026-10-26")!, habits: [HabitDef(name: "Agua", criterion: "2,5 L"), HabitDef(name: "Sueño")])
    let r = Parse.week(t, key: "2026-W44")
    #expect(r.habits.map(\.name) == ["Agua", "Sueño"])
    #expect(r.objetivos == ["", "", ""])
    #expect(t.contains("## 2. Mirar atrás") && !t.contains("dataviewjs"))
    #expect(Edit.toggleHabit(t, habit: "Agua", day: 0) != nil)
}

@Test func icsEvents() {
    let m = Parse.mounjaro(mounjaroFixture)
    let tasks = Parse.tasks("- [ ] Dentista 📅 2026-10-20", file: "x.md")
    let today = DayKey.date("2026-10-19")!
    let ev = ICS.events(ReminderSources(mounjaro: m, tasks: tasks), plan: ReminderPlan(), today: today)
    #expect(ev.first { $0.uid == "mounjaro" }?.rule == "FREQ=DAILY;INTERVAL=9")
    #expect(DayKey.string(ev.first { $0.uid == "mounjaro" }!.start) == "2026-10-19") // atrasado: empieza hoy
    #expect(ev.contains { $0.title == "Dentista" && $0.minutes == nil })
    let ics = ICS.build(ev)
    #expect(ics.contains("DTSTART;VALUE=DATE:20261020"))
    #expect(ics.contains("RRULE:FREQ=MONTHLY;BYMONTHDAY=-1"))
}

@Test func projection() {
    var w = WeightData(initialKg: 136, goalKg: 90, start: nil, records: [])
    w.records = [
        WeightRecord(date: DayKey.date("2026-06-24")!, kg: 114.7, note: ""),
        WeightRecord(date: DayKey.date("2026-09-30")!, kg: 106, note: ""),
    ]
    let r = w.ratePerMonth(window: 120)!
    #expect(r < -2 && r > -3)
    #expect(w.projectedGoalDate(window: 120) != nil)
}

@Test func projectionRange() throws {
    var w = WeightData(initialKg: 120, goalKg: 90, start: nil, records: [])
    w.records = [("2026-05-01", 118.0), ("2026-07-01", 112.0), ("2026-08-15", 108.0), ("2026-09-30", 105.0)]
        .map { WeightRecord(date: DayKey.date($0.0)!, kg: $0.1, note: "") }
    let p = try #require(w.projection())
    #expect(p.ratePerMonth < 0)
    #expect(p.earliest <= p.date && p.date <= p.latest)
    #expect(p.date > w.last!.date)
    // sin bajada o ya en objetivo: sin proyección
    w.records = w.records.reversed().enumerated().map { WeightRecord(date: w.records[$0.offset].date, kg: $0.element.kg, note: "") }
    #expect(w.projection() == nil)
    w.goalKg = 200
    #expect(w.projection() == nil)
}

/// Copia temporal del vault de prueba, para que los tests en paralelo no se pisen.

@MainActor @Test func realVaultCopy() throws {
    guard let path = ProcessInfo.processInfo.environment["VAULT_COPY"] else { return }
    let store = Store(root: try tempVaultCopy(path))
    print("PESOS", store.weight.records.count, store.weight.last?.kg ?? 0, "DOSIS", store.mounjaro.doses.count,
          "NEXT", store.mounjaro.next.map(DayKey.string) ?? "-", "TAREAS", store.tasks.count, "REVS", store.reviews.keys.sorted(),
          "HABITOS", store.habitNames, "NOTAS", store.notes.count, "NALA", store.nala.visits.count, "PLAN", store.plan.kcal,
          "HITOS", store.milestones.count)
    #expect(store.weight.records.count >= 9 && store.mounjaro.doses.count >= 26)
    #expect(store.habitNames.count == 5)
    print("LINKS", store.outLinks.values.reduce(0) { $0 + $1.count }, "INICIO->", store.outLinks["Inicio.md"]?.count ?? 0, "BACK(Peso)", store.backLinks["Cambio físico/Peso.md"]?.count ?? 0, "CASA", store.casa.reformas.rows.count, store.casa.compras.rows.count, store.casa.electros.rows.count)
    #expect(store.outLinks.values.reduce(0) { $0 + $1.count } >= 15)
    #expect(store.casa.reformas.rows.count == 2)
    store.addWeight(date: DayKey.date("2026-10-31")!, kg: 104.9, note: "prueba")
    store.addDose(date: DayKey.date("2026-10-19")!, dose: 7.5, site: "Abdomen derecho", note: "prueba")
    store.createReview(key: "2026-W44", monday: DayKey.date("2026-10-26")!)
    let aguaBefore = store.reviews["2026-W43"]?.habits.first { $0.name == "Agua" }?.days[0] ?? false
    store.toggleHabit(key: "2026-W43", habit: "Agua", day: 0)
    #expect(store.weight.last?.kg == 104.9)
    #expect(store.mounjaro.last?.site == "Abdomen derecho")
    #expect(store.reviews["2026-W44"] != nil)
    #expect(store.reviews["2026-W43"]?.habits.first { $0.name == "Agua" }?.days[0] == !aguaBefore)
}


@Test func moneyParsing() {
    #expect(Money.parse("1.000") == 1000)
    #expect(Money.parse("2000 €") == 2000)
    #expect(Money.parse("1.234,50") == 1234.5)
    #expect(Money.parse("") == 0)
}

@Test func casaParseAndEdit() throws {
    let c = Parse.casa(casaFixture)
    #expect(c.reformas.rows.count == 2 && c.reformas.header.count == 6)
    #expect(c.compras.rows.filter { !($0.cells.first ?? "").isEmpty }.count == 1)
    #expect(c.electros.rows.count == 1)
    #expect(Money.parse(c.reformas.value(c.reformas.rows[1], "Coste estimado")) == 1000)

    let row = c.reformas.rows[1]
    let changed = try #require(Edit.setSectionCell(casaFixture, section: "Reformas", line: row.line, expectFirst: "Pintar techo", column: "Estado", value: "Hecho"))
    let again = Parse.casa(changed)
    #expect(again.reformas.value(again.reformas.rows[1], "Estado") == "Hecho")
    #expect(again.reformas.value(again.reformas.rows[0], "Estado") == "Idea")
    #expect(Edit.setSectionCell(casaFixture, section: "Reformas", line: row.line, expectFirst: "Otra", column: "Estado", value: "x") == nil)

    let added = try #require(Edit.addRow(casaFixture, section: "Compras", cells: ["Mesa", "Salón", "Baja", "300", "IKEA", "Idea"]))
    let after = Parse.casa(added)
    #expect(after.compras.rows.contains { $0.cells.first == "Mesa" })
    #expect(added.contains("| Sillon piel | Salon    |   Media   |             940 | Natuzzi | Idea   |\n| Mesa |"))
}

@Test func linkExtraction() {
    let text = "Ver [[Peso]] y [[Mapa de VictorBrain.excalidraw\\|Mapa]] y [[Nota#sección]] y [[Carpeta/Otra|alias]]\n```\n[[NoEnCodigo]]\n```\n![[Imagen]]"
    #expect(Links.extract(text) == ["Peso", "Mapa de VictorBrain.excalidraw", "Nota", "Otra", "Imagen"])
}

@Test func graphLayoutBounds() {
    let edges = [(0, 1), (1, 2), (2, 0), (3, 0)]
    let a = GraphLayout.compute(count: 5, edges: edges)
    let b = GraphLayout.compute(count: 5, edges: edges)
    #expect(a == b && a.count == 5)
    #expect(a.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 })
    func d(_ i: Int, _ j: Int) -> Double { hypot(a[i].x - a[j].x, a[i].y - a[j].y) }
    #expect(d(0, 1) < d(3, 4) || d(0, 3) < d(3, 4)) // el aislado queda más lejos que los conectados
    #expect(GraphLayout.compute(count: 0, edges: []).isEmpty)
    #expect(GraphLayout.compute(count: 1, edges: []).count == 1)
}

@Test func markdownBlocks() {
    let blocks = MDParser.blocks("---\ntipo: hub\n---\n# Título\n\n- [ ] tarea\n- [x] hecha\n\n| a | b |\n| --- | --- |\n| [[X\\|alias]] | 2 |\n\n```dataviewjs\ncode\n```\n> [!INFO] aviso")
    #expect(blocks.count == 7)
}


@Test func namedTablesAndPeople() {
    let text = "# Personas\n## Contactos\n| Persona | Relación | Cumpleaños | Última vez |\n| --- | --- | --- | --- |\n| Sergio | Amigo | 1990-10-17 | 2026-10-12 |\n| Gora | Hermano | 02-17 |  |\n\n```\n| no | tabla |\n```\n## Otra\n| A |\n| - |\n| 1 |"
    let t = Parse.tables(text)
    #expect(t.count == 2 && t[0].title == "Contactos" && t[0].rows.count == 2 && t[1].title == "Otra")
    let (_, people) = Parse.people(text)
    #expect(people.count == 2)
    #expect(people[0].lastContact == DayKey.date("2026-10-12"))
    let today = DayKey.date("2026-10-19")!
    let b = people[0].nextBirthday(from: today)!
    #expect(DayKey.string(b.date) == "2027-10-17" && b.age == 37)
    #expect(DayKey.string(people[1].nextBirthday(from: today)!.date) == "2027-02-17" && people[1].nextBirthday(from: today)!.age == nil)
}

@Test func dosePeriods() {
    let m = Parse.mounjaro("---\ncada_dias: 9\n---\n| Fecha | Dosis | Zona | N |\n|--|--|--|--|\n| 2026-01-01 | 2,5 mg | A | |\n| 2026-01-10 | 2,5 mg | A | |\n| 2026-02-01 | 5 mg | A | |\n| 2026-03-01 | 5 mg | A | |")
    let w = [WeightRecord(date: DayKey.date("2026-01-01")!, kg: 100, note: ""), WeightRecord(date: DayKey.date("2026-02-01")!, kg: 96, note: ""), WeightRecord(date: DayKey.date("2026-03-05")!, kg: 91, note: "")]
    let p = m.periods(weights: w)
    #expect(p.count == 2 && p[0].mg == 2.5 && p[0].count == 2 && p[1].count == 2)
    #expect(p[0].startKg == 100 && p[0].endKg == 96 && p[0].lostKg == 4)
    #expect(p[1].endKg == 91 && p[1].lostKg == 5)
}

@Test func moreReminderEvents() {
    let people = [Person(name: "Sergio", relation: "", birthday: "1990-10-17", lastContact: nil, line: 1)]
    let src = ReminderSources(people: people, documents: [("Pasaporte", DayKey.date("2026-12-01")!)], events: [("Boda", DayKey.date("2026-11-20")!)])
    let ev = ICS.events(src, plan: ReminderPlan(mounjaro: false, review: false, monthlyWeight: false, tasks: false, nala: false), today: DayKey.date("2026-10-19")!)
    #expect(ev.count == 3)
    let ics = ICS.build(ev)
    #expect(ics.contains("RRULE:FREQ=YEARLY") && ics.contains("TRIGGER:-P30D") && ics.contains("TRIGGER:-P7D"))
    #expect(ics.contains("DTSTART;VALUE=DATE:20271017"))
}


@Test func weightSmoothingDampensSpike() {
    let d0 = DayKey.today()
    var w = WeightData()
    w.records = [
        WeightRecord(date: d0, kg: 100, note: ""),
        WeightRecord(date: DayKey.adding(days: 30, to: d0), kg: 98, note: ""),
        WeightRecord(date: DayKey.adding(days: 60, to: d0), kg: 101, note: ""),
    ]
    let s = w.smoothed(halfLifeDays: 30)
    #expect(s.count == 3)
    #expect(s[0].kg == 100)
    #expect(abs(s[1].kg - 99) < 0.001)
    #expect(s[2].kg < 101 && s[2].kg > 99)
    #expect(WeightData().smoothed().isEmpty)
}

@Test func baseQueryFiltersAndSorts() {
    let meta: [String: [String: String]] = [
        "A/Uno.md": ["tipo": "proyecto", "estado": "Activo", "coste": "30"],
        "A/Dos.md": ["tipo": "proyecto", "estado": "pausa", "coste": "5"],
        "A/Tres.md": ["tipo": "proyecto", "estado": "activo"],
        "A/Cuatro.md": ["tipo": "proyecto", "estado": "activo", "coste": "100"],
    ]
    let paths = meta.keys.sorted()
    var v = BaseView(name: "x")
    v.conditions = [BaseCondition(key: "estado", op: .equals, value: "ACTIVO")]
    v.sortKey = "coste"
    #expect(BaseQuery.apply(v, paths: paths, meta: meta, modified: [:]).map { ($0 as NSString).lastPathComponent } == ["Uno.md", "Cuatro.md", "Tres.md"])
    v.ascending = false   // sin valor sigue al final
    #expect(BaseQuery.apply(v, paths: paths, meta: meta, modified: [:]).map { ($0 as NSString).lastPathComponent } == ["Cuatro.md", "Uno.md", "Tres.md"])
    v.conditions = [BaseCondition(key: "coste", op: .empty)]
    #expect(BaseQuery.apply(v, paths: paths, meta: meta, modified: [:]) == ["A/Tres.md"])
    v.conditions = []; v.text = "dos"; v.sortKey = "Nota"
    #expect(BaseQuery.apply(v, paths: paths, meta: meta, modified: [:]) == ["A/Dos.md"])
}

@Test func linkContextFindsLinkingLine() {
    let text = "---\ntipo: x\n---\n# Título\n```\n[[Nala]] en código\n```\n- [ ] Llevar a [[nala|la gata]] al vet\nOtra [[Casa]]"
    #expect(LinkContext.line(in: text, linkingTo: "Nala") == "Llevar a la gata al vet")
    #expect(LinkContext.line(in: text, linkingTo: "Casa") == "Otra Casa")
    #expect(LinkContext.line(in: text, linkingTo: "Nada") == nil)
}
