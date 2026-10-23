import Foundation
import Testing
@testable import VOTsidian

// MARK: - Medicación: varios medicamentos, diarios, periódicos y «si hace falta»

private func day(_ s: String) -> Date { DayKey.date(s)! }

@Test func frequencyColumnIsUnderstood() {
    #expect(Medication.every("1") == 1 && Medication.every("diaria") == 1 && Medication.every("Cada día") == 1)
    #expect(Medication.every("7") == 7 && Medication.every("semanal") == 7 && Medication.every("cada 2 semanas") == 14 && Medication.every("9 días") == 9)
    #expect(Medication.every("") == 0 && Medication.every("Si hace falta") == 0 && Medication.every("según necesidad") == 0)
    #expect(Medication.times("09:00, 21:00") == ["09:00", "21:00"] && Medication.times("9:00 y 14:30") == ["9:00", "14:30"])
    #expect(Medication.minutes("09:00") == 540 && Medication.minutes("21.30") == 1290 && Medication.minutes("noche") == nil)
    #expect(Medication(name: "x", every: 1, times: ["09:00", "21:00"]).frequencyText == "Cada día · 09:00, 21:00")
    #expect(Medication(name: "x", form: "Pluma inyectable").isInjection && !Medication(name: "x", form: "Pastilla").isInjection)
}

/// Nota nueva con una pastilla dos veces al día, una vitamina diaria, una inyección semanal y un analgésico si hace falta.
private func newNote() throws -> String {
    var t = try #require(Starter.text(forKey: "medicacion"))
    for m in [Medication(name: "Metformina", dose: "850 mg", form: "Pastilla", every: 1, times: ["09:00", "21:00"]),
              Medication(name: "Vitamina D", dose: "1 cápsula", form: "Cápsula", every: 1),
              Medication(name: "Ozempic", dose: "0,5 mg", form: "Inyección", every: 7),
              Medication(name: "Ibuprofeno", dose: "400 mg", form: "Pastilla", every: 0)] {
        t = try #require(Edit.addMedication(t, m, current: nil))
    }
    return t
}

@Test func newNoteHoldsSeveralMedications() throws {
    var t = try newNote()
    #expect(Edit.addMedication(t, Medication(name: "vitamina d"), current: nil) == nil)   // no se repite el nombre
    let take: [(String, String, String, String)] = [("2026-10-20", "Ozempic", "0,5 mg", "Abdomen izquierdo"), ("2026-10-26", "Metformina", "850 mg", ""),
                                                    ("2026-10-26", "Vitamina D", "1 cápsula", ""), ("2026-10-27", "Metformina", "850 mg", "")]
    for (d, n, dose, site) in take {
        t = try #require(Edit.addIntake(t, date: day(d), med: n, dose: dose, site: site, note: "", replaceSameDay: false))
    }
    let m = Parse.medicacion(t)
    #expect(!m.legacy && m.name == "Medicación" && m.meds.map(\.name) == ["Metformina", "Vitamina D", "Ozempic", "Ibuprofeno"])
    #expect(m.meds[0].perDay == 2 && m.meds[3].asNeeded && m.intakes.count == 4)
    // el periódico es el principal: Inicio, «Me pinché hoy» y la gráfica de dosis siguen a ese
    #expect(m.main?.name == "Ozempic" && m.doses.count == 1 && m.last?.site == "Abdomen izquierdo")
    let today = day("2026-10-27")
    let ozempic = m.meds[2]
    #expect(m.next(of: ozempic).map(DayKey.string) == "2026-10-27" && m.daysUntil(ozempic, today: today) == 0)
    // hoy: falta una toma de metformina, la vitamina D y el pinchazo; el ibuprofeno nunca está pendiente
    let pending = m.pending(today: today)
    #expect(pending.map(\.med.name) == ["Metformina", "Vitamina D", "Ozempic"] && pending[0].left == 1)
    // cumplimiento: solo cuenta lo diario y no cuenta hoy
    let a = try #require(m.adherence(m.meds[1], today: today))
    #expect(a.done == 1 && a.total == 1)   // empezó el 26 (su primera toma) y ese día se tomó
    #expect(m.adherence(ozempic, today: today) == nil)
}

@Test func sameDayRules() throws {
    var t = try newNote()
    // una inyección el mismo día se corrige; una pastilla de varias tomas al día se suma
    t = try #require(Edit.addIntake(t, date: day("2026-10-20"), med: "Ozempic", dose: "0,5 mg", site: "A", note: "", replaceSameDay: true))
    t = try #require(Edit.addIntake(t, date: day("2026-10-20"), med: "Ozempic", dose: "1 mg", site: "B", note: "", replaceSameDay: true))
    t = try #require(Edit.addIntake(t, date: day("2026-10-20"), med: "Metformina", dose: "850 mg", site: "", note: "", replaceSameDay: false))
    t = try #require(Edit.addIntake(t, date: day("2026-10-20"), med: "Metformina", dose: "850 mg", site: "", note: "", replaceSameDay: false))
    let m = Parse.medicacion(t)
    #expect(m.intakes(of: m.meds[2]).map(\.dose) == ["1 mg"] && m.taken(m.meds[0], on: day("2026-10-20")) == 2)
}

@Test func oldNoteReadsAsOneInjectionAndUpgrades() throws {
    let old = Parse.medicacion(medicacionFixture)
    #expect(old.legacy && old.name == "Mounjaro" && old.meds.count == 1 && old.meds[0].every == 9 && old.meds[0].isInjection)
    #expect(old.doses.count == 2 && old.intakes.allSatisfy { $0.med == "Mounjaro" } && old.last?.site == "Abdomen izquierdo")
    // en la nota de antes los pinchazos se siguen apuntando por posición
    let more = try #require(Edit.addDose(medicacionFixture, date: day("2026-10-18"), dose: 7.5, site: "Abdomen derecho", note: ""))
    #expect(more.contains("| 2026-10-18 | 7,5 mg | Abdomen derecho |  |") && Parse.medicacion(more).doses.count == 3)
    // al añadir otro medicamento la nota pasa al formato nuevo sin perder nada
    let up = try #require(Edit.addMedication(medicacionFixture, Medication(name: "Vitamina D", dose: "1 cápsula", form: "Cápsula", every: 1), current: old.meds[0]))
    let m = Parse.medicacion(up)
    #expect(!m.legacy && m.name == "Medicación" && m.meds.map(\.name) == ["Mounjaro", "Vitamina D"])
    #expect(m.meds[0].every == 9 && m.meds[0].dose == "7,5 mg" && m.meds[0].isInjection)
    #expect(m.intakes.count == 2 && m.intakes.allSatisfy { $0.med == "Mounjaro" } && m.main?.name == "Mounjaro" && m.doses.count == 2)
    #expect(up.contains("## Medicamentos") && up.contains("| Fecha | Medicamento | Dosis | Zona | Notas |") && up.contains("cada_dias: 9"))
    #expect(up.range(of: "## Medicamentos")!.lowerBound < up.range(of: "## Registro")!.lowerBound)
    // y se sigue escribiendo bien en las dos tablas
    let next = try #require(Edit.addIntake(up, date: day("2026-10-20"), med: "Vitamina D", dose: "1 cápsula", site: "", note: "", replaceSameDay: true))
    #expect(Parse.medicacion(next).intakes.last?.med == "Vitamina D" && Parse.medicacion(next).meds.count == 2)
}

@Test func remindersPerMedicationAndTime() throws {
    var t = try newNote()
    t = try #require(Edit.addIntake(t, date: day("2026-10-20"), med: "Ozempic", dose: "0,5 mg", site: "", note: "", replaceSameDay: true))
    var m = Parse.medicacion(t)
    m.meds[1].end = day("2026-10-30")   // la vitamina D acaba
    let ev = ICS.events(ReminderSources(medicacion: m), plan: ReminderPlan(), today: day("2026-10-21"))
    let meds = ev.filter { $0.uid.hasPrefix("med-") }
    #expect(meds.count == 4)   // metformina ×2 horas, vitamina D y Ozempic; el ibuprofeno no avisa
    #expect(meds.filter { $0.title.hasPrefix("Tomar Metformina") }.compactMap(\.minutes).sorted() == [540, 1260])
    #expect(meds.first { $0.title.hasPrefix("Pinchazo Ozempic") }.map { DayKey.string($0.start) } == "2026-10-27")
    let vitamin = try #require(meds.first { $0.title.hasPrefix("Tomar Vitamina D") })
    #expect(vitamin.rule == "FREQ=DAILY;INTERVAL=1;UNTIL=20261030")
    let planned = Notifier.plan([vitamin], now: day("2026-10-21"), today: day("2026-10-21")).map(\.fire)
    #expect(planned.count == 10 && planned.allSatisfy { $0 <= day("2026-10-31") })   // del 21 al 30, nada después
}

@MainActor @Test func takingAndAlertsOnAStore() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("med-\(UUID().uuidString)")
    let root = tmp.appendingPathComponent("V")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Cambio físico"), withIntermediateDirectories: true)
    try newNote().write(to: root.appendingPathComponent(VaultPath.medicacion), atomically: true, encoding: .utf8)
    let store = Store(root: root, backups: tmp.appendingPathComponent("C"))
    let today = DayKey.today()
    let metformina = try #require(store.medicacion.meds.first)
    // dos casillas: marcar suma, desmarcar quita la última
    store.take(metformina); store.take(metformina)
    #expect(store.medicacion.taken(metformina, on: today) == 2)
    store.untake(metformina)
    #expect(store.medicacion.taken(metformina, on: today) == 1)
    // aviso de lo diario que falta y del pinchazo sin registros (aún sin fecha: no avisa)
    let alerts = store.alerts(today: today)
    #expect(alerts.contains { $0.text == "Hoy falta tomar: Metformina, Vitamina D" })
    let vitamina = try #require(store.medicacion.meds.first { $0.name == "Vitamina D" })
    store.take(vitamina)
    let one = try #require(store.alerts(today: today).first { $0.text.hasPrefix("Hoy falta tomar") })
    #expect(one.action == .take("Metformina"))
    #expect(store.perform(one.action!))
    #expect(!store.alerts(today: today).contains { $0.text.hasPrefix("Hoy falta tomar") })
    // el periódico: «Me pinché hoy» va al principal con su dosis, y el aviso sale cuando toca
    store.injectToday(date: DayKey.adding(days: -8, to: today))
    #expect(store.medicacion.last?.dose == "0,5 mg" && store.medicacion.daysUntilNext == -1)
    #expect(store.alerts(today: today).contains { $0.text == "Pinchazo de Ozempic con 1 día de retraso" && $0.action == .injectToday })
}
