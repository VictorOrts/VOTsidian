import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Fechas naturales, agenda y enlaces

@Test func naturalDates() {
    let today = DayKey.date("2026-10-19")! // lunes
    func t(_ s: String) -> (String, String?) { let r = NaturalDate.extract(s, today: today); return (r.text, r.date.map(DayKey.string)) }
    #expect(t("llamar al dentista el viernes") == ("llamar al dentista", "2026-10-23"))
    #expect(t("pagar 25/11") == ("pagar", "2026-11-25"))
    #expect(t("revisar en 3 días") == ("revisar", "2026-10-22"))
    #expect(t("mañana comprar pan") == ("comprar pan", "2026-10-20"))
    #expect(t("reunión el lunes") == ("reunión", "2026-10-26"))
    #expect(t("cita 3 de noviembre") == ("cita", "2026-11-03"))
    #expect(t("pasado mañana llamar") == ("llamar", "2026-10-21"))
    #expect(t("entregar el 25") == ("entregar", "2026-10-25"))
    #expect(t("renovar 2027-01-05 pasaporte") == ("renovar pasaporte", "2027-01-05"))
    #expect(t("hoy revisar correo") == ("revisar correo", "2026-10-19"))
    #expect(t("5/1") == ("", "2027-01-05"))
    #expect(t("tomar 5 g de magnesio") == ("tomar 5 g de magnesio", nil))
    #expect(t("sin fecha aquí") == ("sin fecha aquí", nil))
}

@MainActor @Test func agendaDiaryAndLinkRepairOnCopy() throws {
    guard let path = ProcessInfo.processInfo.environment["VAULT_COPY"] else { return }
    let store = Store(root: try tempVaultCopy(path))
    let today = DayKey.today()
    let range = store.agenda(from: today, to: DayKey.adding(days: 400, to: today))
    let kinds = Set(range.values.flatMap { $0 }.map(\.kind.rawValue))
    print("AGENDA kinds", kinds.sorted(), "días con algo", range.count)
    #expect(kinds.contains("doseNext") && kinds.contains("birthday"))

    // nota del día
    let day = DayKey.date("2026-11-05")!
    store.appendToDiary(day, text: "Primera")
    store.appendToDiary(day, text: "Segunda")
    let diary = store.read(Store.diaryPath(day))
    #expect(diary.hasPrefix("---\ntipo: diario\nfecha: 2026-11-05\n---") && diary.contains("Primera") && diary.hasSuffix("Segunda\n"))
    #expect(store.notes.contains { $0.path == "Diario/2026-11-05.md" })
    #expect(store.agenda(from: day, to: day)[DayKey.string(day)]?.contains { $0.kind == .diary } == true)

    // tarea con fecha desde el calendario + aplazar
    store.addTask("Probar calendario", due: day)
    let task = try #require(store.tasks.first { $0.text == "Probar calendario" })
    #expect(task.due == day)
    store.reschedule(task, to: DayKey.date("2026-11-06")!)
    #expect(store.tasks.first { $0.text == "Probar calendario" }?.due == DayKey.date("2026-11-06"))

    // enlaces: [[Medicos]] se repara a Médico; las pantallas no cuentan como rotas
    store.edit("Revisiones/Revisión semanal 2026-W43.md") { Edit.setValue($0, after: "**Logros:**", value: "ver [[Medicos]] y [[Tareas]] y [[Inexistente]]") }
    let broken = store.brokenLinks()
    #expect(broken.contains { $0.target == "Medicos" && $0.suggestion == "Médico" })
    #expect(!broken.contains { $0.target == "Tareas" })
    #expect(broken.contains { $0.target == "Inexistente" && $0.suggestion == nil })
    #expect(store.repairLinks() == 1)
    #expect(store.read("Revisiones/Revisión semanal 2026-W43.md").contains("[[Médico]]"))
    #expect(store.fuzzyResolve("Medicos") == VaultPath.medico)
}

@Test func recurringTasks() throws {
    let today = DayKey.date("2026-10-19")!
    #expect(DayKey.string(Recurrence.next(after: DayKey.date("2026-10-01"), rule: "month", today: today)!) == "2026-11-01")
    #expect(DayKey.string(Recurrence.next(after: DayKey.date("2026-10-05"), rule: "week", today: today)!) == "2026-10-19")
    #expect(DayKey.string(Recurrence.next(after: nil, rule: "3 days", today: today)!) == "2026-10-22")
    #expect(Recurrence.describe("2 weeks") == "cada 2 semanas" && Recurrence.describe("month") == "cada mes")

    let text = "# T\n- [ ] Pagar alquiler 📅 2026-11-01 🔁 every month\n- [ ] Otra"
    let task = Parse.tasks(text, file: "a.md")[0]
    #expect(task.recurrence == "month" && task.text == "Pagar alquiler" && DayKey.string(task.due!) == "2026-11-01")
    let done = try #require(Edit.completeRecurring(text, task: task, today: today))
    #expect(done.contains("- [x] Pagar alquiler 📅 2026-11-01 🔁 every month [completion:: 2026-10-19]"))
    #expect(done.contains("\n- [ ] Pagar alquiler 📅 2026-12-01 🔁 every month\n- [ ] Otra"))
    let all = Parse.tasks(done, file: "a.md")
    #expect(all.filter { !$0.done && $0.text == "Pagar alquiler" }.count == 1)
    // editar conserva la repetición
    let edited = try #require(Edit.updateTask(text, task: task, newText: "Pagar alquiler piso", due: DayKey.date("2026-11-02")))
    #expect(edited.contains("- [ ] Pagar alquiler piso 📅 2026-11-02 🔁 every month"))
    // inbox
    let inbox = try #require(Edit.addInboxTask("## Pendiente de clasificar\n- [ ] x", task: "Regar", due: DayKey.date("2026-10-22"), recurrence: "3 days"))
    #expect(inbox.contains("- [ ] Regar 📅 2026-10-22 🔁 every 3 days"))
}

@Test func naturalRecurrence() {
    let today = DayKey.date("2026-10-19")!
    func p(_ s: String) -> (String, String?, String?) { let r = NaturalDate.extractTask(s, today: today); return (r.text, r.recurrence, r.date.map(DayKey.string)) }
    #expect(p("pagar el alquiler cada mes") == ("pagar el alquiler", "month", "2026-11-19"))
    #expect(p("regar las plantas cada 3 días") == ("regar las plantas", "3 days", "2026-10-22"))
    #expect(p("gimnasio cada lunes") == ("gimnasio", "week", "2026-10-26"))
    #expect(p("revisión todos los meses el 5") == ("revisión", "month", "2026-11-05"))
    #expect(p("llamar mañana") == ("llamar", nil, "2026-10-20"))
}
