import Foundation
import Testing
@testable import VOTsidian

// MARK: - Sincronización con Calendar (EventKit): la parte que no necesita permisos

@Test func alarmTriggersBecomeSeconds() {
    typealias S = CalendarEventSpec
    #expect(S.seconds("PT9H") == 32_400 && S.seconds("PT0S") == 0 && S.seconds("-P30D") == -2_592_000 && S.seconds("-P1D") == -86_400)
    #expect(S.seconds("-P1W") == -604_800 && S.seconds("-PT15M") == -900 && S.seconds("P1DT2H") == 93_600)
    #expect(S.seconds("") == nil && S.seconds("9H") == nil && S.seconds("P") == nil && S.seconds("-P1X") == nil && S.seconds("-P30") == nil)
}

@Test func recurrenceRulesAreUnderstood() throws {
    typealias R = CalendarEventSpec.Recurrence
    let daily = try #require(R.parse("FREQ=DAILY;INTERVAL=7;UNTIL=20261231"))
    #expect(daily.frequency == .daily && daily.interval == 7 && daily.until == DayKey.date("2026-12-31"))
    let weekly = try #require(R.parse("FREQ=WEEKLY;BYDAY=SU"))
    #expect(weekly.frequency == .weekly && weekly.weekday == 1 && weekly.interval == 1 && weekly.until == nil)
    #expect(R.parse("FREQ=WEEKLY;BYDAY=FR")?.weekday == 6 && R.parse("FREQ=WEEKLY;BYDAY=SA")?.weekday == 7)
    let monthly = try #require(R.parse("FREQ=MONTHLY;BYMONTHDAY=-1"))
    #expect(monthly.frequency == .monthly && monthly.monthDay == -1)
    #expect(R.parse("FREQ=YEARLY")?.frequency == .yearly && R.parse("FREQ=DAILY;INTERVAL=0")?.interval == 1)
    #expect(R.parse("FREQ=HOURLY") == nil && R.parse("") == nil && R.parse("INTERVAL=2") == nil)
}

@Test func reminderEventsBecomeCalendarSpecs() throws {
    let day = try #require(DayKey.date("2026-10-20"))
    // de día completo: empieza y acaba el mismo día, avisa a las 9:00 y los extra van antes
    let doc = CalendarEventSpec(ICSEvent(uid: "doc-1", title: "Caduca: DNI", notes: "n", start: day, minutes: nil, rule: nil, extraTriggers: ["-P30D"]))
    #expect(doc.allDay && doc.start == day && doc.end == day && doc.alarms == [32_400, -2_592_000] && doc.recurrence == nil && doc.uid == "doc-1")
    // con hora: a esa hora, 15 minutos, y se repite
    let med = CalendarEventSpec(ICSEvent(uid: "med-1", title: "Tomar X", notes: "", start: day, minutes: 21 * 60 + 30, rule: "FREQ=DAILY;INTERVAL=2"))
    #expect(!med.allDay && DayKey.calendar().component(.hour, from: med.start) == 21 && DayKey.calendar().component(.minute, from: med.start) == 30)
    #expect(med.end.timeIntervalSince(med.start) == 900 && med.alarms == [0] && med.recurrence?.interval == 2)
}

@Test func fingerprintChangesOnlyWithWhatCalendarShows() throws {
    let day = try #require(DayKey.date("2026-10-20"))
    func spec(_ title: String = "A", start: Date? = nil, rule: String? = nil, triggers: [String] = []) -> CalendarEventSpec {
        CalendarEventSpec(ICSEvent(uid: "u", title: title, notes: "n", start: start ?? day, minutes: nil, rule: rule, extraTriggers: triggers))
    }
    #expect(spec().fingerprint == spec().fingerprint)
    #expect(spec().fingerprint != spec("B").fingerprint && spec().fingerprint != spec(start: DayKey.adding(days: 1, to: day)).fingerprint)
    #expect(spec().fingerprint != spec(rule: "FREQ=YEARLY").fingerprint && spec().fingerprint != spec(triggers: ["-P1D"]).fingerprint)
    #expect(spec(rule: "FREQ=WEEKLY;BYDAY=MO").fingerprint != spec(rule: "FREQ=WEEKLY;BYDAY=TU").fingerprint)
}

@Test func calendarPlanCreatesUpdatesAndRemoves() throws {
    let day = try #require(DayKey.date("2026-10-20"))
    func spec(_ uid: String, _ title: String) -> CalendarEventSpec {
        CalendarEventSpec(ICSEvent(uid: uid, title: title, notes: "", start: day, minutes: nil, rule: nil))
    }
    let (a, b, c) = (spec("a", "A"), spec("b", "B"), spec("c", "C"))
    // a ya está y no cambió; b ya está pero cambió; c es nuevo; z sobra
    let plan = CalendarPlan.diff(desired: [a, spec("b", "B nuevo"), c], known: ["a": a.fingerprint, "b": b.fingerprint], present: ["a", "b", "z"])
    #expect(plan.create.map(\.uid) == ["c"] && plan.update.map(\.uid) == ["b"] && plan.stale == ["z"])
    // sin historial de huellas, lo que ya está se actualiza una vez
    #expect(CalendarPlan.diff(desired: [a], known: [:], present: ["a"]).update.map(\.uid) == ["a"])
    // dos avisos con el mismo identificador valen como uno
    #expect(CalendarPlan.diff(desired: [a, spec("a", "otro")], known: [:], present: []).create.map(\.title) == ["A"])
    #expect(CalendarPlan.diff(desired: [], known: [:], present: []) == CalendarPlan.Actions())
    // lo suelto que ya pasó se queda como historial; lo futuro y las series se quitan
    let today = DayKey.today()
    #expect(!CalendarPlan.shouldRemove(start: DayKey.adding(days: -3, to: today), recurring: false, today: today))
    #expect(CalendarPlan.shouldRemove(start: today, recurring: false, today: today) && CalendarPlan.shouldRemove(start: DayKey.adding(days: -300, to: today), recurring: true, today: today))
}

@MainActor @Test func everyRealReminderMapsToCalendar() throws {
    let store = Store(root: try syntheticVault())
    store.createSampleTemplates()
    let events = ICS.events(store.reminderSources(), plan: ReminderPlan())
    #expect(events.count > 5)
    for e in events {
        let s = CalendarEventSpec(ICSEvent(uid: e.uid, title: e.title, notes: e.notes, start: e.start, minutes: e.minutes, rule: e.rule, extraTriggers: e.extraTriggers))
        #expect(e.rule == nil || s.recurrence != nil, "\(e.uid) tiene una repetición que EventKit no entiende: \(e.rule ?? "")")
        #expect(s.alarms.count == 1 + e.extraTriggers.count, "\(e.uid) tiene un aviso que no se entiende")
        #expect(s.end >= s.start && !s.uid.isEmpty && s.uid.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }, "\(e.uid)")
    }
    // los identificadores no se repiten: cada aviso es un evento
    #expect(Set(events.map(\.uid)).count == events.count)
}

@MainActor @Test func calendarSyncNeedsTheAppBundle() async {
    #expect(!CalendarSync.available)   // con swift test no hay .app ni permiso declarado: no se pide nada
    await #expect(throws: CalendarSync.Failure.self) { try await CalendarSync.sync([]) }
    #expect(CalendarSync.Report().text == "Todo al día." && CalendarSync.Report(created: 1, updated: 2, removed: 1).text == "1 nuevo, 2 actualizados, 1 quitado.")
}
