import Foundation
import Testing
@testable import VOTsidian

// MARK: - Historial de notas, restaurar copias y enlaces rotos

@Test func backupEntriesReadDateAndKind() throws {
    let base = URL(fileURLWithPath: "/tmp/Copias")
    let auto = BackupEntry(url: base.appendingPathComponent("V-auto-2026-10-21"))
    let manual = BackupEntry(url: base.appendingPathComponent("V-manual-2026-10-21-1430.dmg"))
    let before = BackupEntry(url: base.appendingPathComponent("V-manual-2026-10-22-091502-antes-de-restaurar"))
    #expect(auto.isAuto && !auto.encrypted && !auto.hasTime && auto.date == DayKey.date("2026-10-21"))
    let manualDate = try #require(manual.date)
    #expect(manual.encrypted && manual.hasTime && DayKey.calendar().component(.hour, from: manualDate) == 14)
    #expect(before.beforeRestore && before.label.hasPrefix("Antes de restaurar"))
}

@Test func lineDiffMarksAddedAndRemoved() {
    let d = LineDiff.lines(from: "a\nb\nc", to: "a\nc\nd")
    #expect(d.map(\.kind) == [.same, .removed, .same, .added])
    #expect(d.map(\.text) == ["a", "b", "c", "d"])
    let c = LineDiff.counts(d)
    #expect(c.added == 1 && c.removed == 1)
}

@MainActor @Test func noteHistoryAndRestoreOnCopy() async throws {
    let store = try undoVault()
    let fm = FileManager.default
    try fm.createDirectory(at: store.backupsFolder, withIntermediateDirectories: true)
    func snapshot(_ name: String) { Store.copyVault(from: store.root, to: store.backupsFolder.appendingPathComponent("V-\(name)")) }

    #expect(store.writeNote("A.md", text: "# A\nversión 1\n"))
    snapshot("auto-2026-10-01")
    snapshot("auto-2026-10-02")                       // mismo texto: no sale repetida
    #expect(store.writeNote("A.md", text: "# A\nversión 2\n"))
    snapshot("manual-2026-10-03-1200")
    #expect(store.writeNote("A.md", text: "# A\nversión 3\n"))

    let entries = store.backupEntries().filter { !$0.name.contains(DayKey.string(Date())) }   // sin la automática de hoy
    #expect(entries.map(\.name) == ["V-manual-2026-10-03-1200", "V-auto-2026-10-02", "V-auto-2026-10-01"])
    let h = Store.noteHistory("A.md", in: entries, password: nil)
    #expect(h.versions.map(\.text) == ["# A\nversión 2\n", "# A\nversión 1\n"] && h.locked == 0)

    // restaurar toda la carpeta: vuelve el texto, se conserva lo nuevo y queda copia «antes de restaurar»
    #expect(store.writeNote("Nueva.md", text: "creada después\n"))
    let msg = await store.restoreBackup(try #require(entries.last))
    #expect(msg.contains("Restaurados"))
    #expect(store.read("A.md") == "# A\nversión 1\n")
    #expect(store.read("Nueva.md") == "creada después\n")
    let safety = try #require(store.backupEntries().first { $0.beforeRestore })
    #expect((try? String(contentsOf: safety.url.appendingPathComponent("A.md"), encoding: .utf8)) == "# A\nversión 3\n")
}

@MainActor @Test func brokenLinksOfferCandidatesAndFixes() throws {
    let store = try undoVault()
    #expect(store.writeNote("Notas/Receta de lentejas.md", text: "# Lentejas\n"))
    #expect(store.writeNote("Notas/Índice.md", text: "Ver [[Receta de lentejaz]] y [[Algo nuevo]]\n"))
    let broken = store.brokenLinks()
    #expect(store.brokenLinkCount == broken.count && store.sidebarCounts()[.enlaces] == broken.count)   // el contador barato cuadra con la lista
    let typo = try #require(broken.first { $0.target == "Receta de lentejaz" })
    #expect(typo.candidates.first == "Receta de lentejas")
    store.fixLink(typo, to: "Receta de lentejas")
    #expect(store.read("Notas/Índice.md").contains("[[Receta de lentejas]]"))
    let missing = try #require(store.brokenLinks().first { $0.target == "Algo nuevo" })
    #expect(store.createMissingNote(missing) == "Notas/Algo nuevo.md")
    #expect(store.brokenLinks().isEmpty)
    #expect(Store.editDistance(Array("casa"), Array("cosa")) == 1)
    // con límite corta en cuanto lo pasa, pero por debajo da la distancia exacta
    #expect(Store.editDistance(Array("kitten"), Array("sitting")) == 3)
    #expect(Store.editDistance(Array("kitten"), Array("sitting"), limit: 3) == 3)
    #expect(Store.editDistance(Array("kitten"), Array("sitting"), limit: 1) == 2)
}
