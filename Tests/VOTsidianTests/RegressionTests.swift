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

@Test func labParameterWithoutResultsDoesNotExist() {
    #expect(LabParameter(name: "HbA1c", results: []) == nil)
}
