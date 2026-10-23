import Foundation
import Testing
@testable import VOTsidian

// Casos de la revisión de finales de octubre 2026: tablas con `\|`, gastos, repeticiones, notas sin leer, deshacer en grupo y copias.

@Test func cellEditsKeepEscapedPipes() {
    let row = "| [[Nota\\|alias]] | 10 | Fijo |"
    #expect(MD.setCell(row, col: 1, value: "20") == "| [[Nota\\|alias]] | 20 | Fijo |")
    // El valor nuevo con una `|` suelta se escapa; no parte la celda.
    let set = MD.setCell(row, col: 2, value: "a | b")
    #expect(MD.cells(set) == ["[[Nota|alias]]", "10", "a | b"])
    let section = "## Compras\n| Cosa | Estado |\n| :-- | :-- |\n| [[Sofá\\|sofá nuevo]] | pendiente |\n"
    let edited = Edit.setSectionCell(section, section: "Compras", line: 3, expectFirst: "[[Sofá|sofá nuevo]]", column: "Estado", value: "comprado")
    #expect(edited?.contains("| [[Sofá\\|sofá nuevo]] | comprado") == true)
}

@Test func numbersWithThousandsSeparators() {
    #expect(MD.number("1.234,5") == 1234.5)
    #expect(MD.number("1,234.5") == 1234.5)
    #expect(MD.number("1.234.567") == 1234567)
    #expect(MD.number("105,5 kg") == 105.5)
    #expect(MD.number("7.5 mg") == 7.5)
    #expect(MD.number("-3") == -3)
}

@Test func expenseAmountAndDayOfMonth() throws {
    let cats = testBudgetLines.map(\.0)
    let today = try #require(DayKey.date("2026-10-23"))
    let gym = try #require(ExpenseParser.parse("gym o2 40", categories: cats, today: today))
    #expect(gym.amount == 40 && gym.category == "Gym + fibra")
    // «el 20» es el de este mes, no el del mes que viene un año atrás.
    #expect(ExpenseParser.parse("el 20 pan 3", categories: cats, today: today).map { DayKey.string($0.date) } == "2026-10-20")
    #expect(ExpenseParser.parse("pan 3 el 20", categories: cats, today: today).map { DayKey.string($0.date) } == "2026-10-20")
    // En los próximos días se respeta (pago por adelantado); «el 31» de un mes de 30 días busca el último 31 que pasó.
    #expect(ExpenseParser.parse("comunidad 60 el 25", categories: cats, today: today).map { DayKey.string($0.date) } == "2026-10-25")
    let nov = try #require(DayKey.date("2026-11-10"))
    #expect(ExpenseParser.parse("luz 50 el 31", categories: cats, today: nov).map { DayKey.string($0.date) } == "2026-10-31")
    // Fechas con mes siguen yendo al año pasado si caen lejos en el futuro.
    #expect(ExpenseParser.parse("25/11 pan 3", categories: cats, today: today).map { DayKey.string($0.date) } == "2025-11-25")
    #expect(ExpenseParser.parse("25/11/2026 pan 3", categories: cats, today: today).map { DayKey.string($0.date) } == "2026-11-25")
}

@Test func recurringTasksWithPriorityAfterOrWhenDone() throws {
    let today = try #require(DayKey.date("2026-10-23"))
    let text = "- [ ] regar 🔁 every week ⏫ 📅 2026-10-20\n- [ ] limpiar 🔁 every 2 weeks when done 📅 2026-10-01\n"
    let tasks = Parse.tasks(text, file: "x.md")
    #expect(tasks.map(\.text) == ["regar", "limpiar"])
    #expect(tasks[0].recurrence == "week" && tasks[0].priority == 3)
    let next = try #require(Edit.completeRecurring(text, task: tasks[0], today: today))
    #expect(next.contains("- [ ] regar ⏫ 📅 2026-10-27 🔁 every week"))
    // «when done»: la siguiente se cuenta desde hoy, no desde la fecha que tenía.
    let done = try #require(Edit.completeRecurring(text, task: tasks[1], today: today))
    #expect(done.contains("📅 2026-11-06 🔁 every 2 weeks when done"))
    #expect(Recurrence.describe("2 weeks when done") == "cada 2 semanas")
}

@Test func otherTaskBulletsAndObsidianTasksFields() throws {
    let text = "* [ ] con asterisco 📅 2026-10-30\n1. [x] numerada ✅ 2026-10-02\n+ [ ] con más 🛫 2026-10-01 ➕ 2026-09-30\n"
    let tasks = Parse.tasks(text, file: "x.md")
    #expect(tasks.map(\.text) == ["con asterisco", "numerada", "con más"])
    #expect(tasks[1].done && tasks[1].completed.map(DayKey.string) == "2026-10-02")
    let undone = try #require(Edit.setTask(text, task: tasks[1], done: false))
    #expect(undone.contains("1. [ ] numerada\n"))
    let today = try #require(DayKey.date("2026-10-23"))
    let marked = try #require(Edit.setTask(text, task: tasks[0], done: true, on: today))
    #expect(marked.hasPrefix("* [x] con asterisco 📅 2026-10-30 [completion:: 2026-10-23]"))
    // Cambiar el texto conserva las fechas de inicio y creación.
    let updated = try #require(Edit.updateTask(text, task: tasks[2], newText: "con más cosas", due: nil))
    #expect(updated.contains("+ [ ] con más cosas 🛫 2026-10-01 ➕ 2026-09-30"))
}

@Test func tableRowsFromFormsEscapePipes() throws {
    let oct15 = try #require(DayKey.date("2026-10-15")), oct18 = try #require(DayKey.date("2026-10-18"))
    let peso = try #require(Edit.addWeight(pesoFixture, date: oct15, kg: 104, note: "tras | viaje"))
    #expect(Parse.weight(peso).records.first { $0.kg == 104 }?.note == "tras | viaje")
    let dosis = try #require(Edit.addDose(medicacionFixture, date: oct18, dose: 7.5, site: "Muslo", note: "a|b"))
    #expect(Parse.medicacion(dosis).doses.last?.note == "a|b")
}

@MainActor @Test func createBudgetDoesNotOverwriteAnUnscannedNote() throws {
    let store = try undoVault()
    let rel = store.budgetPath("2026-12")
    try "---\ntipo: presupuesto\n---\n# Mío\n\n## Movimientos\n| Fecha | Importe | Partida | Nota |\n| :-- | --: | :-- | :-- |\n| 2026-12-01 | 9 | Otros | |\n"
        .write(to: store.url(rel).creatingParent(), atomically: true, encoding: .utf8)
    // La app aún no la ha leído (iCloud la acaba de traer): no se crea otra encima.
    #expect(store.createBudget("2026-12"))
    #expect(store.read(rel).contains("# Mío"))
    #expect(store.budget("2026-12")?.moves.count == 1)
}

@MainActor @Test func leftoverTransferIsOneUndoStepAndCreatesTheProperty() throws {
    let store = try undoVault()
    try "# Finanzas\n".write(to: store.url(VaultPath.finanzas).creatingParent(), atomically: true, encoding: .utf8)
    store.reload()
    store.addExpense(100, category: "Alimentación", note: "", date: try #require(DayKey.date("2026-09-10")))
    let before = try #require(store.budget("2026-09"))
    let steps = store.undoStack.count
    store.transferLeftover(before, amount: 50)
    #expect(store.undoStack.count == steps + 1)
    #expect(store.noteMeta[VaultPath.finanzas]?["fondo_emergencia_eur"] == "50")
    #expect(store.budget("2026-09")?.saved == 50)
    store.undo()
    #expect(store.read(VaultPath.finanzas) == "# Finanzas\n")
    #expect(store.budget("2026-09")?.saved == 0)
}

@MainActor @Test func addTasksSkipsRepeatsInsideTheSameBatch() throws {
    let store = try undoVault()
    store.addTasks([("Llamar", nil), ("Llamar", nil), ("Otra", nil)])
    let inbox = store.read(VaultPath.inbox)
    #expect(inbox.components(separatedBy: "- [ ] Llamar").count == 2)
    #expect(inbox.contains("- [ ] Otra"))
}

@MainActor @Test func conflictCopyKeepsWhatWasTyped() throws {
    let store = try undoVault()
    #expect(store.writeNote("Ideas.md", text: "# Ideas\n"))
    let copy = try #require(store.saveConflictCopy("Ideas.md", text: "# Ideas\nlo mío\n"))
    #expect(copy.hasPrefix("Ideas (copia en conflicto "))
    #expect(store.read(copy) == "# Ideas\nlo mío\n")
    #expect(store.conflictCopies.contains { $0.path == copy })
    #expect(store.saveConflictCopy("Ideas.md", text: "otra") != copy)   // no pisa la anterior
}

@MainActor @Test func alertsHaveStableIdsAndBackupFailuresShow() throws {
    let store = try undoVault()
    #expect(store.alerts().map(\.id) == store.alerts().map(\.id))
    #expect(Set(store.alerts().map(\.id)).count == store.alerts().count)
    store.backupFinished(ok: false, day: "2026-10-23")
    #expect(store.alerts().contains { $0.screen == .ajustes && $0.text.contains("23/10/2026") && $0.level == .urgent })
    store.backupFinished(ok: true, day: "2026-10-23")
    #expect(!store.alerts().contains { $0.text.contains("copia de seguridad") })
}

@MainActor @Test func lastBackupAgeAndStampFormat() throws {
    let store = try undoVault()
    #expect(store.daysSinceLastBackup() == nil)
    #expect(Store.stamp("yyyy-MM-dd").range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)
    try FileManager.default.createDirectory(at: store.backupsFolder.appendingPathComponent("\(store.vaultName)-auto-2026-10-18"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: store.backupsFolder.appendingPathComponent("\(store.vaultName)-manual-2026-10-20-0930"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: store.backupsFolder.appendingPathComponent("Otra-auto-2026-10-22"), withIntermediateDirectories: true)
    #expect(store.daysSinceLastBackup(today: try #require(DayKey.date("2026-10-23"))) == 3)
}

@MainActor @Test func budgetCacheFollowsEdits() throws {
    let store = try undoVault()
    store.addExpense(10, category: "Alimentación", note: "", date: try #require(DayKey.date("2026-09-10")))
    #expect(store.budget("2026-09")?.moves.count == 1)
    store.addExpense(5, category: "Alimentación", note: "", date: try #require(DayKey.date("2026-09-11")))
    #expect(store.budget("2026-09")?.moves.count == 2)
}
