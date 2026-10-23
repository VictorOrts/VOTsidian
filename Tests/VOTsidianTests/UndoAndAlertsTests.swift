import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

@MainActor @Test func undoAndAlertsOnCopy() throws {
    guard let path = ProcessInfo.processInfo.environment["VAULT_COPY"] else { return }
    let store = Store(root: try tempVaultCopy(path))
    let before = store.read(VaultPath.peso)
    let kgBefore = store.weight.last?.kg
    store.addWeight(date: DayKey.date("2026-11-30")!, kg: 103.3, note: "undo")
    #expect(store.canUndo && store.weight.last?.kg == 103.3)
    store.undo()
    #expect(store.read(VaultPath.peso) == before && store.weight.last?.kg == kgBefore)
    // nota nueva + renombrar + papelera
    let rel = try #require(store.createNote(folder: "Proyectos", name: "Prueba", template: "Proyecto"))
    #expect(store.noteMeta[rel]?["tipo"] == "proyecto")
    let renamed = try #require(store.renameNote(rel, to: "Prueba 2"))
    #expect(store.notes.contains { $0.path == renamed })
    store.trashNote(renamed)
    #expect(!store.notes.contains { $0.path == renamed })
    print("ALERTS", store.alerts().map(\.text))
    print("DOCS", store.documents.count, "PEOPLE", store.people.count, "EVENTS", store.events.count, "ATT", store.attachments.keys.sorted())
    #expect(!store.people.isEmpty)
    #expect(store.attachmentURL("Simple.numbers") != nil)
    // Salud: Médico.md
    let med = store.read(VaultPath.medico)
    print("SALUD citas", store.tasks.filter { $0.file == VaultPath.medico && !$0.done }.count, "tablas", Parse.tables(med).map(\.title), "meds", Parse.listItems(med, section: "Tratamientos").count)
    let treatments = Parse.listItems(med, section: "Tratamientos").count
    store.edit(VaultPath.medico) { Edit.appendToSection($0, section: "Próximas citas", line: "- [ ] Revisión 📅 2026-12-01") }
    store.edit(VaultPath.medico) { Edit.appendToSection($0, section: "Tratamientos", line: "- Magnesio 300 mg al día") }
    #expect(store.tasks.contains { $0.file == VaultPath.medico && $0.text == "Revisión" })
    #expect(Parse.listItems(store.read(VaultPath.medico), section: "Tratamientos").count == treatments + 1)
}



@MainActor @Test func undoRestoresRenamedNoteAndLinks() throws {
    let store = try undoVault()
    #expect(store.renameNote("B.md", to: "C") == "C.md")
    #expect(store.read("A.md").contains("[[C]]"))
    store.undo()
    #expect(store.read("A.md").contains("[[B]]"))
    #expect(FileManager.default.fileExists(atPath: store.url("B.md").path))
    #expect(!FileManager.default.fileExists(atPath: store.url("C.md").path))
}

@MainActor @Test func undoRestoresTrashedNoteAndLinks() throws {
    let store = try undoVault()
    store.trashNote("B.md")
    #expect(!FileManager.default.fileExists(atPath: store.url("B.md").path))
    #expect(store.canUndo)
    store.undo()
    #expect(FileManager.default.fileExists(atPath: store.url("B.md").path))
    #expect(store.read("A.md").contains("[[B]]"))
}

@MainActor @Test func detectsICloudConflictCopies() {
    let files: Set<String> = ["Casa/Lista.md", "Casa/Lista 2.md", "Semana 2.md", "Notas/Idea (conflicted copy).md", "Otra.md"]
    let hits = files.filter { Store.isConflictCopy($0, existing: files) }
    #expect(hits == ["Casa/Lista 2.md", "Notas/Idea (conflicted copy).md"])
}
