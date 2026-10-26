import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Planificar la semana

@Test func weekPlanLogic() {
    let today = DayKey.date("2026-10-21")!                 // miércoles
    let monday = DayKey.date("2026-10-19")!
    func task(_ text: String, _ due: String?, _ prio: Int = 0, done: Bool = false, sched: String? = nil) -> TaskItem {
        TaskItem(file: "Inbox.md", line: Int.random(in: 1...9999), raw: "- [ ] \(text)", text: text, due: due.flatMap(DayKey.date), scheduled: sched.flatMap(DayKey.date), done: done, priority: prio)
    }
    let all = [task("A", "2026-10-19"), task("B", "2026-10-21", 3), task("C", "2026-10-21"), task("D", "2026-10-18"), task("E", nil), task("F", nil, sched: "2026-10-23"),
               task("G", "2026-10-26"), task("H", "2026-10-22", done: true), task("I", "2026-09-01")]
    let plan = WeekPlan.build(tasks: all, agenda: [:], weekStart: monday, today: today)
    #expect(plan.days.count == 7 && DayKey.string(plan.days[6]) == "2026-10-25")
    #expect(plan.tasks["2026-10-21"]?.map(\.text) == ["B", "C"])                     // la urgente primero
    #expect(plan.tasks["2026-10-19"]?.map(\.text) == ["A"] && plan.tasks["2026-10-23"]?.map(\.text) == ["F"])   // una planeada cuenta en su día
    #expect(plan.overdue.map(\.text) == ["I", "D"])                                  // antes de esta semana, la más antigua primero
    #expect(plan.undated.map(\.text) == ["E"])
    #expect(plan.tasks["2026-10-22"] == nil && plan.load(plan.days[2]) == 2)          // las hechas no salen
    // semana futura: solo lo anterior a hoy es vencido
    let next = WeekPlan.build(tasks: all, agenda: [:], weekStart: DayKey.date("2026-10-26")!, today: today)
    #expect(next.tasks["2026-10-26"]?.map(\.text) == ["G"] && Set(next.overdue.map(\.text)) == ["A", "D", "I"])    // lo de hoy y de esta semana no es vencido
    // semana pasada: lo de esta semana no es vencido
    let prev = WeekPlan.build(tasks: all, agenda: [:], weekStart: DayKey.date("2026-10-12")!, today: today)
    #expect(Set(prev.overdue.map(\.text)) == ["I"] || prev.overdue.map(\.text).sorted() == ["I"])
}

@MainActor @Test func planningActionsOnCopy() throws {
    guard let path = ProcessInfo.processInfo.environment["VAULT_COPY"] else { return }
    let store = Store(root: try tempVaultCopy(path))
    let today = DayKey.today()
    store.addTask("Vieja uno", due: DayKey.adding(days: -9, to: today))
    store.addTask("Vieja dos", due: DayKey.adding(days: -3, to: today), priority: 3)
    store.addTask("Con fecha", due: DayKey.adding(days: 2, to: today))
    let t = try #require(store.tasks.first { $0.text == "Con fecha" })
    store.unschedule(t)
    #expect(store.tasks.first { $0.text == "Con fecha" }?.due == nil)
    store.moveOverdueToToday()
    #expect(store.tasks.filter { $0.text.hasPrefix("Vieja") }.allSatisfy { $0.due == today })
    #expect(store.tasks.first { $0.text == "Vieja dos" }?.priority == 3)
    store.undo()                                                                      // pasar todo a hoy se deshace de una vez
    #expect(store.tasks.filter { $0.text.hasPrefix("Vieja") }.allSatisfy { ($0.due ?? today) < today })
}

@Test func notifierExpandsRecurrencesAndOffsets() {
    let today = DayKey.date("2026-10-19")!
    let now = DayKey.calendar().date(bySettingHour: 8, minute: 0, second: 0, of: today)!
    let shot = ICSEvent(uid: "medicacion", title: "Pinchazo", notes: "", start: DayKey.date("2026-10-20")!, minutes: 540, rule: "FREQ=DAILY;INTERVAL=9")
    let doc = ICSEvent(uid: "doc", title: "Caduca", notes: "", start: DayKey.date("2026-11-10")!, minutes: nil, rule: nil, extraTriggers: ["-P7D"])
    let past = ICSEvent(uid: "old", title: "Viejo", notes: "", start: DayKey.date("2026-10-01")!, minutes: nil, rule: nil)
    let plan = Notifier.plan([shot, doc, past], now: now, today: today)
    let shots = plan.filter { $0.id.hasPrefix("medicacion") }
    #expect(shots.map { DayKey.string($0.fire) } == ["2026-10-20", "2026-10-29", "2026-11-07", "2026-11-16"])
    #expect(plan.contains { $0.id == "doc-2026-11-10--P7D" && DayKey.string($0.fire) == "2026-11-03" })
    #expect(!plan.contains { $0.id.hasPrefix("old") })
    #expect(plan == plan.sorted { $0.fire < $1.fire })
    // En FREQ=WEEKLY, INTERVAL cuenta semanas, no días
    let biweekly = ICSEvent(uid: "quincena", title: "Cada dos semanas", notes: "", start: DayKey.date("2026-10-20")!, minutes: 540, rule: "FREQ=WEEKLY;INTERVAL=2")
    #expect(Notifier.plan([biweekly], now: now, today: today).map { DayKey.string($0.fire) } == ["2026-10-20", "2026-11-03", "2026-11-17"])
}

@Test func dosePeriodsJoinSameDose() {
    let d = { (s: String, dose: String) in Dose(date: DayKey.date(s)!, dose: dose, site: "", note: "") }
    let p = Correlations.dosePeriods([d("2026-10-09", "7,5 mg"), d("2026-09-30", "7,5 mg"), d("2026-09-01", "5 mg"), d("2026-10-18", "10 mg")],
                                     until: DayKey.date("2026-10-24")!)
    #expect(p.map(\.dose) == ["5 mg", "7,5 mg", "10 mg"])
    #expect(p.map { DayKey.string($0.start) } == ["2026-09-01", "2026-09-30", "2026-10-18"])
    #expect(p.map { DayKey.string($0.end) } == ["2026-09-30", "2026-10-18", "2026-10-24"])
    #expect(Correlations.dosePeriods([], until: Date()).isEmpty)
}

@Test func pearsonAndWeekPoints() {
    #expect(Correlations.pearson([1, 2, 3, 4, 5, 6], [2, 4, 6, 8, 10, 12]).map { abs($0 - 1) < 1e-9 } == true)
    #expect(Correlations.pearson([1, 2, 3, 4, 5, 6], [6, 5, 4, 3, 2, 1]).map { abs($0 + 1) < 1e-9 } == true)
    #expect(Correlations.pearson([1, 2, 3], [1, 2, 3]) == nil)           // pocas semanas
    #expect(Correlations.pearson([1, 1, 1, 1, 1, 1], [1, 2, 3, 4, 5, 6]) == nil)   // sin variación

    let mon = DayKey.weekStart(DayKey.date("2026-09-07")!)
    let weights = [WeightRecord(date: mon, kg: 100, note: ""), WeightRecord(date: DayKey.adding(days: 8, to: mon), kg: 98, note: "")]
    let doses = [Dose(date: mon, dose: "5 mg", site: "", note: "")]
    let pts = Correlations.weeks(weights: weights, doses: doses, today: DayKey.adding(days: 13, to: mon), sleep: { _, _ in 6.5 })
    #expect(pts.count == 2)
    #expect(pts[0].kgChange == nil && pts[0].mg == 5 && pts[0].sleep == 6.5)
    #expect(pts[1].kgChange == -2)
}
