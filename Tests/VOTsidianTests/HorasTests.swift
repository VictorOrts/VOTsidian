import Foundation
import Testing
@testable import VOTsidian

// MARK: - Hora en tareas y citas: «a las 17:30»

private func D(_ s: String) -> Date { DayKey.date(s)! }

@Test func timesAreUnderstoodInSpanish() {
    func t(_ s: String) -> Int? { NaturalDate.extractTime(s).minutes }
    #expect(t("dentista a las 17:30") == 17 * 60 + 30 && t("dentista a las 9:05") == 9 * 60 + 5 && t("a la 1") == 13 * 60)
    #expect(t("a las 5 de la tarde") == 17 * 60 && t("a las 9 de la noche") == 21 * 60 && t("a las 10 de la mañana") == 10 * 60)
    #expect(t("a las 5") == 17 * 60 && t("a las 9") == 9 * 60 && t("a las 7") == 7 * 60)      // de 1 a 6 sin más, tarde
    #expect(t("a las 6 de la mañana") == 6 * 60 && t("a las 12 del mediodía") == 12 * 60 && t("a mediodía") == 12 * 60)
    #expect(t("a las 9 y media") == 9 * 60 + 30 && t("a las 10 y cuarto") == 10 * 60 + 15 && t("a las 11 menos cuarto") == 10 * 60 + 45)
    #expect(t("sobre las 16:00") == 16 * 60 && t("reunión 17:30") == 17 * 60 + 30 && t("a las 17h") == 17 * 60 && t("a las 17.30") == 17 * 60 + 30)
    // lo que no es una hora
    #expect(t("pagar 25/11") == nil && t("leer las 3 primeras páginas") == nil && t("a las 25:00") == nil && t("comprar 2 kilos") == nil && t("") == nil)
    #expect(NaturalDate.extractTime("Dentista a las 17:30 sin falta").text == "Dentista sin falta")
}

@Test func tasksAndAppointmentsCarryTheirTime() throws {
    let today = D("2026-10-23")
    let p = NaturalDate.extractTask("llamar al dentista el viernes a las 17:30 urgente", today: today)
    #expect(p.text == "llamar al dentista" && p.date == D("2026-10-30") && p.time == 17 * 60 + 30 && p.priority == 3)
    let c = NaturalDate.extractDateTime("dermatólogo el 29/10 a las 9 y media", today: today)
    #expect(c.text == "dermatólogo" && c.date == D("2026-10-29") && c.time == 9 * 60 + 30)
    #expect(QuickCommand.parse("cita dentista el 29/10 a las 17:30", today: today) == .appointment("dentista", D("2026-10-29"), 17 * 60 + 30))
    #expect(QuickCommand.parse("tarea revisión coche mañana a las 9", today: today) == .task("revisión coche", D("2026-10-24"), nil, 0, 9 * 60, false))
    #expect(QuickCommand.appointment("dentista", D("2026-10-29"), 17 * 60 + 30).summary.hasSuffix("a las 17:30"))
}

@Test func taskTimeIsWrittenReadAndKept() throws {
    let line = Edit.taskLine("Dentista", due: D("2026-11-02"), time: 17 * 60 + 30, recurrence: nil, priority: 3)
    #expect(line == "- [ ] Dentista ⏫ 📅 2026-11-02 ⏰ 17:30")
    #expect(Edit.taskLine("Sin fecha", due: nil, time: 600) == "- [ ] Sin fecha")      // la hora solo va con fecha
    let t = try #require(Parse.tasks(line, file: "x").first)
    #expect(t.text == "Dentista" && t.time == 17 * 60 + 30 && t.due == D("2026-11-02") && t.priority == 3)
    #expect(Parse.tasks("- [ ] Mal ⏰ 25:99 📅 2026-11-02", file: "x").first?.time == nil)
    // editar la tarea sin tocar la hora la conserva; con hora nueva la cambia; con .some(nil) la quita
    let kept = try #require(Edit.updateTask(line, task: t, newText: "Dentista Ana", due: D("2026-11-03")))
    #expect(Parse.tasks(kept, file: "x").first.map { $0.time == 17 * 60 + 30 && $0.text == "Dentista Ana" } == true)
    let moved = try #require(Edit.updateTask(line, task: t, newText: "Dentista", due: D("2026-11-02"), time: .some(9 * 60)))
    #expect(Parse.tasks(moved, file: "x").first?.time == 9 * 60)
    let removed = try #require(Edit.updateTask(line, task: t, newText: "Dentista", due: D("2026-11-02"), time: .some(nil)))
    #expect(Parse.tasks(removed, file: "x").first?.time == nil && !removed.contains("⏰"))
    // una tarea que se repite conserva la hora en la siguiente
    let weekly = "- [ ] Pilates 📅 2026-10-23 ⏰ 19:00 🔁 every week"
    let w = try #require(Parse.tasks(weekly, file: "x").first)
    let next = try #require(Edit.completeRecurring(weekly, task: w, today: D("2026-10-23")))
    #expect(Parse.tasks(next, file: "x").contains { !$0.done && $0.time == 19 * 60 && $0.due == D("2026-10-30") })
}

@MainActor @Test func timedAppointmentsInCalendarAlertsAndCalendarApp() throws {
    let store = Store(root: try syntheticVault())
    let today = DayKey.today()
    let tomorrow = DayKey.adding(days: 1, to: today)
    store.addAppointment("Dentista", date: tomorrow, time: 17 * 60 + 30)
    store.addAppointment("Análisis", date: tomorrow, time: 8 * 60)
    store.addAppointment("Recoger receta", date: tomorrow)
    let cita = try #require(store.tasks.first { $0.text == "Dentista" })
    #expect(cita.file == VaultPath.medico && cita.time == 17 * 60 + 30)
    // el día se ordena: lo de todo el día primero, después por hora
    let day = try #require(store.agenda(from: tomorrow, to: tomorrow)[DayKey.string(tomorrow)])
    let titles = day.filter { $0.kind == .appointment }.map(\.title)
    #expect(titles == ["Recoger receta", "Análisis", "Dentista"] && day.first { $0.title == "Dentista" }?.timeText == "17:30")
    // el aviso dice la hora
    #expect(store.alerts().contains { $0.text == "Dentista mañana a las 17:30" })
    // Calendar: evento con hora, aviso el día antes y una hora antes
    let ev = ICS.events(store.reminderSources(), plan: ReminderPlan(), today: today)
    let e = try #require(ev.first { $0.title == "Dentista" })
    #expect(e.minutes == 17 * 60 + 30 && e.extraTriggers == ["-P1D", "-PT1H"])
    #expect(ev.first { $0.title == "Recoger receta" }.map { $0.minutes == nil && $0.extraTriggers == ["-P1D"] } == true)
    let spec = CalendarEventSpec(e)
    #expect(!spec.allDay && DayKey.calendar().component(.hour, from: spec.start) == 17 && spec.alarms == [0, -86_400, -3600])
    // notificaciones de macOS: a la hora, una hora antes y el día antes
    let planned = Notifier.plan([e], now: today, today: today).filter { $0.title == "Dentista" }
    #expect(planned.contains { $0.body.hasPrefix("Dentro de 1 h.") && DayKey.calendar().component(.hour, from: $0.fire) == 16 })
    #expect(planned.contains { DayKey.calendar().component(.hour, from: $0.fire) == 17 && DayKey.calendar().component(.minute, from: $0.fire) == 30 })
    // una nota de visita con «hora:»
    store.writeNote("Salud/Visita.md", text: "---\ntipo: cita_medica\nfecha: \(DayKey.string(tomorrow))\nhora: 12:15\n---\n# Visita\n")
    #expect(store.agenda(from: tomorrow, to: tomorrow)[DayKey.string(tomorrow)]?.first { $0.title == "Visita" }?.minutes == 12 * 60 + 15)
}

// MARK: 🔕 sin aviso en Calendar

@MainActor @Test func mutedTasksStayInTheAppButNotInCalendar() throws {
    let p = NaturalDate.extractTask("gimnasio mañana a las 19:00 sin aviso", today: D("2026-10-23"))
    #expect(p.text == "gimnasio" && p.muted && p.time == 19 * 60 && p.date == D("2026-10-24"))
    #expect(QuickCommand.parse("tarea gimnasio el viernes sin avisar", today: D("2026-10-23")) == .task("gimnasio", D("2026-10-30"), nil, 0, nil, true))
    #expect(!NaturalDate.extractTask("llamar a Ana", today: D("2026-10-23")).muted)
    // en la nota y de vuelta
    let line = Edit.taskLine("Gimnasio", due: D("2026-10-27"), time: 19 * 60, muted: true)
    #expect(line == "- [ ] Gimnasio 📅 2026-10-27 ⏰ 19:00 🔕")
    let t = try #require(Parse.tasks(line, file: "x").first)
    #expect(t.muted && t.text == "Gimnasio")
    // editar sin decir nada lo conserva; se puede quitar
    #expect(Parse.tasks(try #require(Edit.updateTask(line, task: t, newText: "Gym", due: t.due)), file: "x").first?.muted == true)
    #expect(Parse.tasks(try #require(Edit.updateTask(line, task: t, newText: "Gym", due: t.due, muted: false)), file: "x").first?.muted == false)
    // al repetirse, la siguiente sigue sin aviso
    let weekly = "- [ ] Pilates 📅 2026-10-23 ⏰ 19:00 🔕 🔁 every week"
    let w = try #require(Parse.tasks(weekly, file: "x").first)
    #expect(w.muted && w.recurrence == "week")
    #expect(Parse.tasks(try #require(Edit.completeRecurring(weekly, task: w, today: D("2026-10-23"))), file: "x").contains { !$0.done && $0.muted })
    // en la app sí, en Calendar no
    let store = Store(root: try syntheticVault())
    let tomorrow = DayKey.adding(days: 1, to: DayKey.today())
    store.addTask("Con aviso", due: tomorrow)
    store.addTask("Callada", due: tomorrow, muted: true)
    #expect(store.agenda(from: tomorrow, to: tomorrow)[DayKey.string(tomorrow)]?.contains { $0.title == "Callada" } == true)
    let ev = ICS.events(store.reminderSources(), plan: ReminderPlan(), today: DayKey.today())
    #expect(ev.contains { $0.title == "Con aviso" } && !ev.contains { $0.title == "Callada" })
}
