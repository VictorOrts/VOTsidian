import Foundation
import Testing
@testable import VOTsidian

// MARK: - Mi día: duración (⏱), plan del día por horas y semana

private func D(_ s: String) -> Date { DayKey.date(s)! }

@Test func durationsAreWrittenReadAndKept() throws {
    #expect(TaskDuration.parse("45m") == 45 && TaskDuration.parse("2h") == 120 && TaskDuration.parse("1h30m") == 90 && TaskDuration.parse("1h30") == 90)
    #expect(TaskDuration.parse("90min") == 90 && TaskDuration.parse("45") == nil && TaskDuration.parse("3m") == nil && TaskDuration.parse("30h") == nil && TaskDuration.parse("") == nil)
    #expect(TaskDuration.text(90) == "1h30m" && TaskDuration.text(120) == "2h" && TaskDuration.text(45) == "45m")
    #expect(TaskDuration.human(90) == "1 h 30 min" && TaskDuration.human(60) == "1 h" && TaskDuration.human(20) == "20 min")
    let line = Edit.taskLine("Informe", due: D("2026-10-26"), time: 10 * 60, priority: 2, muted: true, duration: 90)
    #expect(line == "- [ ] Informe 🔼 📅 2026-10-26 ⏰ 10:00 ⏱ 1h30m 🔕")
    let t = try #require(Parse.tasks(line, file: "x").first)
    #expect(t.text == "Informe" && t.duration == 90 && t.time == 10 * 60 && t.muted && t.priority == 2)
    // sin fecha también vale (lo que se calcula que dura no depende del día), y con el selector de variación de algunos teclados
    #expect(Parse.tasks("- [ ] Leer ⏱️ 30m", file: "x").first.map { $0.duration == 30 && $0.text == "Leer" } == true)
    #expect(Parse.tasks("- [ ] Raro ⏱ 99h", file: "x").first?.duration == nil)
    // editar sin decir nada la conserva; se cambia y se quita
    let kept = try #require(Edit.updateTask(line, task: t, newText: "Informe Q3", due: t.due, time: .some(11 * 60)))
    #expect(Parse.tasks(kept, file: "x").first.map { $0.duration == 90 && $0.time == 11 * 60 } == true)
    #expect(Parse.tasks(try #require(Edit.updateTask(line, task: t, newText: "Informe", due: t.due, duration: .some(30))), file: "x").first?.duration == 30)
    let removed = try #require(Edit.updateTask(line, task: t, newText: "Informe", due: t.due, duration: .some(nil)))
    #expect(!removed.contains("⏱") && Parse.tasks(removed, file: "x").first?.duration == nil)
    // al repetirse, la siguiente dura lo mismo
    let weekly = "- [ ] Pilates 📅 2026-10-23 ⏰ 19:00 ⏱ 1h 🔁 every week"
    let w = try #require(Parse.tasks(weekly, file: "x").first)
    #expect(Parse.tasks(try #require(Edit.completeRecurring(weekly, task: w, today: D("2026-10-23"))), file: "x").contains { !$0.done && $0.duration == 60 && $0.time == 19 * 60 })
}

@Test func durationsAreUnderstoodInSpanish() {
    let today = D("2026-10-23")
    func p(_ s: String) -> NaturalDate.ParsedTask { NaturalDate.extractTask(s, today: today) }
    let range = p("reunión con Marta mañana de 10 a 11:30")
    #expect(range.text == "reunión con Marta" && range.time == 10 * 60 && range.duration == 90 && range.date == D("2026-10-24"))
    #expect(p("taller de 5 a 7").time == 17 * 60 && p("taller de 5 a 7").duration == 120)          // de 1 a 6, tarde
    #expect(p("guardia de 22 a 2").duration == nil)                                                 // pasa de medianoche: no se adivina
    let lasting = p("repasar inglés el lunes a las 18:00 durante 45 min")
    #expect(lasting.text == "repasar inglés" && lasting.time == 18 * 60 && lasting.duration == 45 && lasting.date == D("2026-10-26"))
    #expect(p("correr durante 1 hora").duration == 60 && p("correr durante hora y media").duration == 90 && p("siesta durante media hora").duration == 30)
    #expect(p("estudiar durante 2 horas").duration == 120 && p("estudiar durante 1h30").duration == 90 && p("estudiar durante 2 horas y media").duration == 150)
    #expect(p("leer ⏱ 25m").duration == 25 && p("leer ⏱ 25m").text == "leer")
    // lo que no es una duración
    #expect(p("comprar 2 kilos de manzanas").duration == nil)
    #expect(p("llamar a Ana").duration == nil && p("pagar el 5 de noviembre").duration == nil)
}

@Test func dayPlanSplitsTimedAndUnscheduled() {
    let day = D("2026-10-23"), yesterday = D("2026-10-22"), tomorrow = D("2026-10-24")
    let tasks = [
        TaskItem(file: "Inbox.md", line: 1, raw: "", text: "Informe", due: day, scheduled: nil, done: false, time: 10 * 60, duration: 90),
        TaskItem(file: "Inbox.md", line: 2, raw: "", text: "Correo", due: day, scheduled: nil, done: false, time: 9 * 60),
        TaskItem(file: "Inbox.md", line: 3, raw: "", text: "Llamar", due: day, scheduled: nil, done: false, duration: 15),
        TaskItem(file: "Inbox.md", line: 4, raw: "", text: "Vencida", due: yesterday, scheduled: nil, done: false, priority: 3, time: 8 * 60),
        TaskItem(file: "Inbox.md", line: 5, raw: "", text: "Mañana", due: tomorrow, scheduled: nil, done: false),
        TaskItem(file: "Inbox.md", line: 6, raw: "", text: "Hecha", due: day, scheduled: nil, done: true, time: 8 * 60, duration: 60),
        TaskItem(file: VaultPath.medico, line: 7, raw: "", text: "Dentista", due: day, scheduled: nil, done: false, time: 17 * 60 + 30),
    ]
    let agenda = [AgendaItem(id: "cVisita", kind: .appointment, title: "Visita", date: day, minutes: 12 * 60),
                  AgendaItem(id: "bAna", kind: .birthday, title: "Cumpleaños de Ana", date: day)]
    let plan = DayPlan.build(day: day, today: day, tasks: tasks, agenda: agenda, meds: [(id: "1", title: "Tomar Vitamina D", minutes: 9 * 60)])
    #expect(plan.blocks.map(\.title) == ["Hecha", "Tomar Vitamina D", "Correo", "Informe", "Visita", "Dentista"])
    #expect(plan.blocks.first { $0.title == "Correo" }?.duration == DayPlan.defaultDuration && plan.blocks.first { $0.title == "Informe" }?.duration == 90)
    #expect(plan.blocks.first { $0.title == "Dentista" }.map { $0.source == .appointment && $0.movable } == true)   // una cita en Médico es una tarea: se mueve
    #expect(plan.blocks.first { $0.title == "Visita" }.map { $0.source == .appointment && !$0.movable } == true)   // la de una nota propia, no
    #expect(plan.blocks.first { $0.title == "Hecha" }.map { $0.done && !$0.movable && !$0.counts } == true)
    // sin hora: la vencida primero (aunque tuviera hora, era de otro día) y la de hoy después; la de mañana no
    #expect(plan.unscheduled.map(\.text) == ["Vencida", "Llamar"])
    // jornada: Correo 30 + Informe 90 + Visita 30 + Dentista 30 + Llamar 15 (la medicación y lo hecho no cuentan)
    #expect(plan.plannedMinutes == 195 && plan.unestimated == 1)
    // otro día que no es hoy no arrastra lo vencido
    #expect(DayPlan.build(day: tomorrow, today: day, tasks: tasks, agenda: []).unscheduled.map(\.text) == ["Mañana"])
}

@Test func overlappingBlocksShareTheWidth() {
    func b(_ id: String, _ start: Int, _ length: Int) -> TimeBlock { TimeBlock(id: id, title: id, start: start, duration: length, source: .task, kind: .task) }
    let cols = DayPlan.columns([b("a", 600, 60), b("b", 630, 60), b("c", 700, 30), b("d", 800, 30), b("e", 610, 10)])
    // a, e y b se solapan (de 10:00 a 11:30) y caben en dos columnas: b ocupa el hueco que deja e. c y d van solas.
    #expect(cols["a"]! == (0, 2) && cols["e"]! == (1, 2) && cols["b"]! == (1, 2))
    #expect(cols["c"]! == (0, 1) && cols["d"]! == (0, 1))
    #expect(DayPlan.snap(611) == 615 && DayPlan.snap(-40) == 0 && DayPlan.snap(2000) == 24 * 60 - 15)
}

@Test func autoScheduleFillsTheGaps() {
    func task(_ text: String, _ minutes: Int?) -> TaskItem { TaskItem(file: "x", line: 0, raw: text, text: text, due: nil, scheduled: nil, done: false, duration: minutes) }
    let busy = [TimeBlock(id: "m", title: "Reunión", start: 10 * 60, duration: 60, source: .task, kind: .task),
                TimeBlock(id: "h", title: "Hecha", start: 9 * 60, duration: 60, source: .task, kind: .task, done: true)]
    let placed = DayPlan.autoSchedule([task("A", 45), task("B", nil), task("C", 120), task("D", 300)], around: busy, from: 9 * 60 + 5, until: 13 * 60)
    // A 9:15–10:00 (lo hecho no ocupa); B 11:00–11:30, tras la reunión; C (2 h) y D ya no caben antes de las 13:00
    #expect(placed.map(\.task.text) == ["A", "B"] && placed.map(\.start) == [9 * 60 + 15, 11 * 60])
}

@MainActor @Test func myDayInTheStoreAndInCalendar() throws {
    let store = Store(root: try syntheticVault())
    let today = DayKey.today(), tomorrow = DayKey.adding(days: 1, to: today)
    store.addTask(NaturalDate.extractTask("preparar presentación durante 1 hora"), defaultDue: tomorrow)
    store.addTask(NaturalDate.extractTask("llamar al seguro"), defaultDue: tomorrow)
    store.addTask(NaturalDate.extractTask("revisar contrato mañana de 9 a 10:30"))
    var plan = store.dayPlan(tomorrow)
    #expect(plan.blocks.contains { $0.title == "revisar contrato" && $0.start == 9 * 60 && $0.duration == 90 })
    #expect(Set(plan.unscheduled.map(\.text)).isSuperset(of: ["preparar presentación", "llamar al seguro"]))
    // arrastrar a una hora y estirar
    let p = try #require(plan.unscheduled.first { $0.text == "preparar presentación" })
    store.schedule(p, on: tomorrow, at: 16 * 60)
    let placed = try #require(store.tasks.first { $0.text == "preparar presentación" })
    #expect(placed.time == 16 * 60 && placed.duration == 60 && placed.due == tomorrow)
    store.setDuration(placed, 120)
    #expect(store.tasks.first { $0.text == "preparar presentación" }?.duration == 120)
    // Calendar: el evento dura lo que dice ⏱
    let ev = try #require(ICS.events(store.reminderSources(), plan: ReminderPlan(), today: today).first { $0.title == "preparar presentación" })
    #expect(ev.duration == 120 && CalendarEventSpec(ev).end.timeIntervalSince(CalendarEventSpec(ev).start) == 7200)
    #expect(ICS.build([ev]).contains("DURATION:PT120M"))
    // quitar la hora la devuelve a «sin hora»
    store.schedule(try #require(store.tasks.first { $0.text == "preparar presentación" }), on: tomorrow, at: nil)
    #expect(store.dayPlan(tomorrow).unscheduled.contains { $0.text == "preparar presentación" })
    // repartir coloca todas las que caben y se deshace de una vez
    plan = store.dayPlan(tomorrow)
    let before = store.read(VaultPath.inbox)
    let n = store.autoSchedule(plan, from: 8 * 60, until: 20 * 60)
    #expect(n == plan.unscheduled.count && store.dayPlan(tomorrow).unscheduled.isEmpty)
    store.undo()
    #expect(store.read(VaultPath.inbox) == before)
}
