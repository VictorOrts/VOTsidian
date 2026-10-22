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
