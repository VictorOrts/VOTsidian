import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

@Test func identicalTasksAreToggledNearTheirOwnLine() throws {
    let text = "- [ ] Comprar pan\n- [ ] Comprar pan\nfin\n"
    let task = TaskItem(file: "A.md", line: 5, raw: "- [ ] Comprar pan", text: "Comprar pan", due: nil, scheduled: nil, done: false)
    // la línea guardada (5) ya no existe: se elige la coincidencia más cercana, la segunda, no la primera
    let out = try #require(Edit.setTask(text, task: task, done: true))
    #expect(out.hasPrefix("- [ ] Comprar pan\n- [x] Comprar pan [completion::"))
    let del = try #require(Edit.deleteLine(text, raw: "- [ ] Comprar pan", hint: 5))
    #expect(del == "- [ ] Comprar pan\nfin\n")
    let rec = TaskItem(file: "A.md", line: 5, raw: "- [ ] Regar 📅 2026-10-19 🔁 every week", text: "Regar", due: DayKey.date("2026-10-19"), scheduled: nil, done: false, recurrence: "week")
    let rtext = "- [ ] Regar 📅 2026-10-19 🔁 every week\n- [ ] Regar 📅 2026-10-19 🔁 every week\n"
    let rout = MD.lines(try #require(Edit.completeRecurring(rtext, task: rec, today: DayKey.date("2026-10-19")!)))
    #expect(rout[0].hasPrefix("- [ ] Regar") && rout[1].contains("[x]") && rout[2].hasPrefix("- [ ] Regar") && rout.count == 4)
}

@MainActor @Test func undoDoesNotOverwriteExternalChanges() throws {
    let store = try undoVault()
    store.edit("A.md") { $0 + "añadido por la app\n" }
    try "cambiado desde otro programa\n".write(to: store.url("A.md"), atomically: true, encoding: .utf8)
    store.undo()
    #expect(store.read("A.md") == "cambiado desde otro programa\n")
    #expect(store.message?.contains("cambió fuera de la app") == true)
    // sin cambios externos sí se deshace
    store.edit("B.md") { $0 + "x\n" }
    store.undo()
    #expect(store.read("B.md") == "# B\n")
}

@MainActor @Test func dailyBackupRepeatsOnANewDay() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
    let vault = tmp.appendingPathComponent("Notas")
    try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    try "# A\n".write(to: vault.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
    let store = Store(root: vault, backups: tmp.appendingPathComponent("Copias"))
    store.edit("A.md") { $0 + "1\n" }
    let today = store.autoBackupURL(Store.stamp("yyyy-MM-dd"))
    #expect(FileManager.default.fileExists(atPath: today.path))
    // la app sigue abierta al día siguiente: la marca de «ya copiado» es de otro día y se vuelve a copiar
    try FileManager.default.removeItem(at: today)
    store.lastBackupDay = "2000-01-01"
    store.edit("A.md") { $0 + "2\n" }
    #expect(try String(contentsOf: today.appendingPathComponent("A.md"), encoding: .utf8) == "# A\n1\n")
}

@MainActor @Test func backgroundReloadPicksUpExternalChanges() async throws {
    let store = try undoVault()
    #expect(!store.notes.contains { $0.name == "Nueva" })
    let rev = store.revision
    store.reloadInBackground()   // sin cambios: no toca el estado
    try await Task.sleep(for: .milliseconds(400))
    #expect(store.revision == rev)
    try "# Nueva\n- [ ] tarea de fuera\n".write(to: store.url("Nueva.md"), atomically: true, encoding: .utf8)
    store.reloadInBackground()
    for _ in 0..<50 where !store.notes.contains(where: { $0.name == "Nueva" }) { try await Task.sleep(for: .milliseconds(100)) }
    #expect(store.notes.contains { $0.name == "Nueva" } && store.tasks.contains { $0.text == "tarea de fuera" })
}

@MainActor @Test func unreadableNotesAreReportedAndExternalEditsSurviveAppEdits() throws {
    let store = try undoVault()
    try Data([0xFF, 0xFE, 0x00, 0xC3]).write(to: store.url("Rota.md"))   // no es UTF-8
    store.reload()
    #expect(store.unreadableFiles == ["Rota.md"])
    #expect(store.alerts().contains { $0.text.contains("no se puede leer") })
    // la app lee el archivo del disco justo antes de cambiarlo: lo escrito desde fuera no se pierde
    try "# A\nver [[B]]\nlínea de fuera\n".write(to: store.url("A.md"), atomically: true, encoding: .utf8)
    store.edit("A.md") { $0 + "línea de la app\n" }
    #expect(store.read("A.md") == "# A\nver [[B]]\nlínea de fuera\nlínea de la app\n")
}

@MainActor @Test func pathOverridesAndLooseVaultValidity() throws {
    // clave inventada: así no afecta a otros tests que corren a la vez
    #expect(VaultPath.path("clave-de-prueba") == "clave-de-prueba" && VaultPath.peso == "Salud/Peso.md")
    UserDefaults.standard.set(["clave-de-prueba": "Salud/Otro.md"], forKey: "vaultPathOverrides")
    defer { UserDefaults.standard.removeObject(forKey: "vaultPathOverrides") }
    #expect(VaultPath.path("clave-de-prueba") == "Salud/Otro.md" && VaultPath.inbox == "Organización/Inbox.md")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)/Otra")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    #expect(!Store(root: dir).isValid)   // vacía
    try "# Hola\n".write(to: dir.appendingPathComponent("Hola.md"), atomically: true, encoding: .utf8)
    #expect(Store(root: dir).isValid)    // sin Peso.md pero con notas
}

/// Un número de 24 cifras en el plan nutricional llegaba a `Int(_:)` al calcular el % de cada macro y cerraba la app.
@Test @MainActor func hugeNutritionNumbersDoNotCrash() throws {
    let store = Store(root: try syntheticVault())
    store.edit(VaultPath.plan) { _ in
        "---\nkcal_objetivo: 1800\nproteina_g: 999999999999999999999999\ncarbohidratos_g: 150\ngrasas_g: 50\n---\n\n# Plan nutricional\n"
    }
    #expect(store.plan.protein > 1e20)
    #expect(percentText(store.plan.protein * 4 / store.plan.kcal) == "–")
    #expect(percentText(0.426) == "43 %")
    try renderAllScreens(store)
}

/// Un importe diminuto («0,000…01») pasa `Money.parse`; dividir por él daba un número enorme que llegaba a `Int(_:)`
/// (meses del fondo de emergencia, % frente a la media de la partida) y cerraba la app.
@Test @MainActor func tinyAmountsDoNotCrash() throws {
    let store = Store(root: try syntheticVault())
    let tiny = "0," + String(repeating: "0", count: 20) + "1"
    let now = Date(), before = try #require(DayKey.calendar().date(byAdding: .month, value: -1, to: now))
    let b = try #require(store.budget(Budget.monthKey(now)))
    let saving = try #require(b.lines.first { $0.kind == .ahorro })
    store.edit(b.path) { Edit.setSectionCell($0, section: "Partidas", line: saving.line, expectFirst: saving.name, column: "Previsto", value: tiny) }
    #expect((store.budget(Budget.monthKey(now))?.lines.first { $0.kind == .ahorro }?.planned ?? 1) < 1e-15)
    let p = try #require(store.budget(Budget.monthKey(before)))
    for l in p.lines where l.kind == .fijo {
        store.edit(p.path) { Edit.setSectionCell($0, section: "Partidas", line: l.line, expectFirst: l.name, column: "Previsto", value: tiny) }
    }
    // Ingresos casi a cero: la tasa de ahorro del resumen del año.
    let income = try #require(store.budget(Budget.monthKey(now))?.incomes.first)
    for column in ["Previsto", "Real"] {
        store.edit(b.path) { Edit.setSectionCell($0, section: "Ingresos", line: income.line, expectFirst: income.name, column: column, value: tiny) }
    }
    #expect(Money.percent(-1e40) == "–")
    try renderAllScreens(store)
    let year = DayKey.calendar().component(.year, from: now)
    let r = ImageRenderer(content: GastosYearView(year: year, open: { _ in }).environment(store).frame(width: 1000, height: 800))
    #expect(r.cgImage != nil)
}
