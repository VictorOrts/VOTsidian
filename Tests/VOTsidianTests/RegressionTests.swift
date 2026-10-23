import Foundation
import Testing
@testable import VOTsidian

// Casos de revisión: lectura fallida, escritura sobre archivos ilegibles, deshacer de notas nuevas y parámetros vacíos.

@MainActor @Test func unreadableFileIsNotOverwritten() throws {
    let store = try undoVault()
    let bad = store.url("Ilegible.md")
    let bytes = Data([0xFF, 0xFE, 0x00, 0xC3])   // no es UTF-8 válido
    try bytes.write(to: bad)
    #expect(store.readOptional("Ilegible.md") == nil)
    #expect(store.read("Ilegible.md") == "")
    #expect(store.writeNote("Ilegible.md", text: "nuevo") == false)
    #expect(try Data(contentsOf: bad) == bytes)
    #expect(store.message?.contains("No se modificó") == true)
}

@MainActor @Test func missingFileReadsAsNilAndNewNoteUndoesToNothing() throws {
    let store = try undoVault()
    #expect(store.readOptional("No existe.md") == nil)
    #expect(store.writeNote("Nueva.md", text: "# Nueva\n") == true)
    #expect(store.readOptional("Nueva.md") == "# Nueva\n")
    store.undo()
    #expect(!FileManager.default.fileExists(atPath: store.url("Nueva.md").path))
}

// MARK: - Revisión de octubre 2026

@Test func impossibleDatesAreRejectedNotRolledOver() throws {
    #expect(DayKey.date("2026-02-31") == nil)
    #expect(DayKey.dmyDate("31/04/2026") == nil)
    #expect(DayKey.date("2028-02-29") != nil)                      // bisiesto
    let today = try #require(DayKey.date("2026-11-10"))
    let bad = NaturalDate.extract("pagar 31/2", today: today)
    #expect(bad.date == nil)                                        // antes: 3 de marzo
    let el31 = NaturalDate.extract("pagar el 31", today: today)     // noviembre tiene 30 días
    #expect(el31.date.map(DayKey.string) == "2026-12-31")
}

@Test func windowsLineEndingsAreRead() {
    let text = "---\r\ntipo: nota\r\n---\r\n- [ ] Tarea\r\n"
    #expect(MD.frontmatter(text)["tipo"] == "nota")
    #expect(Parse.tasks(text, file: "a.md").map(\.text) == ["Tarea"])
}

@MainActor @Test func trashingANoteKeepsLinksToItsHomonym() throws {
    let store = try undoVault()
    #expect(store.writeNote("A/Ideas.md", text: "# A\n"))
    #expect(store.writeNote("B/Ideas.md", text: "# B\n"))
    #expect(store.writeNote("Índice.md", text: "Ver [[Ideas]]\n"))
    store.trashNote("A/Ideas.md")
    #expect(store.read("Índice.md") == "Ver [[Ideas]]\n")
    #expect(store.resolve("Ideas") == "B/Ideas.md")
}

@MainActor @Test func pendingAutosavesRunWhenFlushed() {
    var saved = 0
    PendingSaves.actions[UUID()] = { saved += 1 }
    PendingSaves.flush()
    PendingSaves.flush()
    #expect(saved == 1 && PendingSaves.actions.isEmpty)
}

// MARK: - Revisión completa (23 oct 2026)

@Test func recurringTaskKeepsPriorityAndSetTaskOnlyTouchesTheBox() throws {
    let raw = "- [ ] Regar ⏫ 📅 2026-10-19 🔁 every week"
    let rec = TaskItem(file: "A.md", line: 0, raw: raw, text: "Regar", due: DayKey.date("2026-10-19"), scheduled: nil, done: false, recurrence: "week", priority: 3)
    let out = MD.lines(try #require(Edit.completeRecurring(raw, task: rec, today: DayKey.date("2026-10-19")!)))
    #expect(out[1].contains("⏫"))

    let odd = "- [ ] Revisar la lista «- [ ] algo»"
    let t = TaskItem(file: "A.md", line: 0, raw: odd, text: "Revisar la lista «- [ ] algo»", due: nil, scheduled: nil, done: false)
    let done = try #require(Edit.setTask(odd, task: t, done: true, on: DayKey.date("2026-10-19")!))
    #expect(done.hasPrefix("- [x] Revisar la lista «- [ ] algo»"))
}

@Test func hugeRelativeNumbersDoNotCrash() throws {
    let today = try #require(DayKey.date("2026-10-19"))
    #expect(NaturalDate.extract("llamar en 99999999999999999999 dias", today: today).date == nil)
    #expect(NaturalDate.extract("llamar en 3 dias", today: today).date.map(DayKey.string) == "2026-10-22")
}

@Test func weightWithoutGoalHasNoGoalNumbers() {
    let w = Parse.weight("| Fecha | Peso |\n| --- | --- |\n| 01/09/2026 | 100 |\n| 01/10/2026 | 96 |\n")
    #expect(!w.hasGoal)
    #expect(w.remainingKg == nil)
    #expect(w.projection() == nil)
    #expect(w.initialKg == 100)
    #expect(w.lostKg == 4)
}

@MainActor @Test func tasksAndIdeasCreateTheInboxWhenMissing() throws {
    let store = try undoVault()
    #expect(store.readOptional(VaultPath.inbox) == nil)
    store.addTask("Comprar pan", due: nil)
    store.addIdea("Una idea")
    let inbox = try #require(store.readOptional(VaultPath.inbox))
    #expect(inbox.contains("- [ ] Comprar pan"))
    #expect(inbox.contains("- Una idea"))
    #expect(store.tasks.contains { $0.text == "Comprar pan" })
}

@MainActor @Test func renameOnlyChangingCase() throws {
    let store = try undoVault()
    #expect(store.renameNote("B.md", to: "b") == "b.md")
    #expect(store.read("A.md").contains("[[b]]"))
}

@Test func unlinkUnderstandsCaseAccentsAndFolders() {
    let text = "Ver [[medico]] y [[Salud/Médico|el médico]]\n[[Inicio]] · [[MÉDICO#citas]]\n[[Médicos]] sigue"
    #expect(Edit.unlink(text, name: "Médico") == "Ver medico y el médico\n[[Inicio]]\n[[Médicos]] sigue")
}

@Test func frontmatterValuesAreQuotedWhenYAMLNeedsIt() throws {
    let text = "---\ntipo: nota\nlista: [a, b]\n---\n"
    var t = try #require(Edit.setFrontmatter(text, key: "area", value: "Casa: cocina"))
    t = try #require(Edit.setFrontmatter(t, key: "rel", value: "[[Otra nota]]"))
    t = try #require(Edit.setFrontmatter(t, key: "cita", value: "dijo \"hola\""))
    t = try #require(Edit.setFrontmatter(t, key: "tipo", value: "#etiqueta"))
    t = try #require(Edit.setFrontmatter(t, key: "lista", value: "[a, c]"))
    #expect(t.contains("area: \"Casa: cocina\"") && t.contains("rel: \"[[Otra nota]]\"") && t.contains("lista: [a, c]"))
    let fm = MD.frontmatter(t)
    #expect(fm["area"] == "Casa: cocina" && fm["rel"] == "[[Otra nota]]" && fm["tipo"] == "#etiqueta")
    #expect(fm["cita"] == "dijo \"hola\"")
    #expect(Edit.setFrontmatter(t, key: "estado", value: "activo")?.contains("estado: activo\n") == true)
}

@Test func monthlySeriesKeepsTheDayAndWeekdaysSkipWeekends() throws {
    let d = { (s: String) in DayKey.date(s)! }
    // Desde el 31 de enero, tres meses después es el 30 de abril (no el 28).
    #expect(Recurrence.next(after: d("2026-01-31"), rule: "month", today: d("2026-04-15")).map(DayKey.string) == "2026-04-30")
    #expect(Recurrence.pinningDay("month", due: d("2026-01-31")) == "month on the 31st")
    #expect(Recurrence.pinningDay("month", due: d("2026-01-15")) == "month")
    #expect(Recurrence.next(after: d("2026-02-28"), rule: "month on the 31st", today: d("2026-02-28")).map(DayKey.string) == "2026-03-31")
    #expect(Recurrence.next(after: d("2026-01-31"), rule: "month on the 31st", today: d("2026-01-31")).map(DayKey.string) == "2026-02-28")
    #expect(Recurrence.describe("month on the 31st") == "cada mes, el día 31")

    // La tarea completada escribe la regla con el día fijo, y la siguiente vuelve al 31.
    let raw = "- [ ] Pagar 📅 2026-01-31 🔁 every month"
    let task = TaskItem(file: "A.md", line: 0, raw: raw, text: "Pagar", due: d("2026-01-31"), scheduled: nil, done: false, recurrence: "month")
    let out = MD.lines(try #require(Edit.completeRecurring(raw, task: task, today: d("2026-01-31"))))
    #expect(out[1] == "- [ ] Pagar 📅 2026-02-28 🔁 every month on the 31st")
    let next = try #require(Parse.tasks(out[1], file: "A.md").first)
    #expect(next.recurrence == "month on the 31st")

    // 2026-10-23 es viernes: el siguiente laborable es el lunes 26.
    #expect(Recurrence.next(after: d("2026-10-23"), rule: "weekday", today: d("2026-10-23")).map(DayKey.string) == "2026-10-26")
    #expect(Recurrence.describe("weekday") == "cada día laborable")
    let p = NaturalDate.extractTask("revisar correo entre semana", today: d("2026-10-24"))   // sábado
    #expect(p.recurrence == "weekday" && p.text == "revisar correo" && p.date.map(DayKey.string) == "2026-10-26")
}
