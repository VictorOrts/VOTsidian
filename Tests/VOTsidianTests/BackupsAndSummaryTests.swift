import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Medidas, autoguardado y resumen

@Test func measuresTemplateAndParse() throws {
    let (t, none) = Measures.parse(Measures.template)
    let table = try #require(t)
    #expect(none.isEmpty && table.header.count == 8)
    var cells = [String](repeating: "", count: table.header.count)
    cells[0] = "19/10/2026"; cells[table.col("cintura")!] = "98,5"; cells[table.col("grasa")!] = "27"
    let added = try #require(Edit.insertTableRow(Measures.template, afterLine: table.lastLine, cells: cells))
    let (_, recs) = Measures.parse(added)
    #expect(recs.count == 1 && recs[0].values["Cintura"] == 98.5 && recs[0].values["Grasa"] == 27 && recs[0].values["Pecho"] == nil)
    // la segunda medición va detrás de la primera
    let (t2, _) = Measures.parse(added)
    let again = try #require(Edit.insertTableRow(added, afterLine: t2!.lastLine, cells: ["19/11/2026", "97", "", "", "", "", "", ""]))
    #expect(Measures.parse(again).records.map { $0.values["Cintura"] } == [98.5, 97])
}

@Test func checkboxToggleSurvivesShiftedLines() throws {
    let before = "- [ ] Uno\n- [ ] Dos\n"
    let shifted = "Línea nueva\n" + before   // alguien añadió una línea arriba
    let out = try #require(Edit.toggleCheckbox(shifted, line: 1, expect: "- [ ] Dos"))   // línea 1 ya no es «Dos»
    #expect(out.contains("- [ ] Uno") && out.contains("- [x] Dos"))
    #expect(Edit.toggleCheckbox(shifted, line: 1, expect: "- [ ] Tres") == nil)
}

@MainActor @Test func quietSavesAreCoalescedAndSummaryWorks() throws {
    guard let path = ProcessInfo.processInfo.environment["VAULT_COPY"] else { return }
    let store = Store(root: try tempVaultCopy(path))
    let before = store.read(VaultPath.peso)
    store.setProperty(VaultPath.peso, key: "objetivo_peso_kg", value: "91", quiet: true)
    store.setProperty(VaultPath.peso, key: "objetivo_peso_kg", value: "92", quiet: true)
    store.setProperty(VaultPath.peso, key: "objetivo_peso_kg", value: "93", quiet: true)
    #expect(store.weight.goalKg == 93)
    store.undo()   // un solo paso de deshacer para los tres guardados seguidos
    #expect(store.read(VaultPath.peso) == before)

    let summary = store.doctorSummary()
    print("SUMMARY\n" + summary)
    #expect(summary.contains("PESO") && summary.contains("MOUNJARO") && summary.contains("HÁBITOS"))

    // archivo de iCloud sin descargar
    let dir = store.url("Casa")
    FileManager.default.createFile(atPath: dir.appendingPathComponent(".Reformas extra.md.icloud").path, contents: Data())
    store.reload()
    #expect(store.pendingDownloads == ["Casa/Reformas extra.md"])
    #expect(store.alerts().contains { $0.text.contains("iCloud") })
}


@MainActor @Test func backupsGoToOneFolderAndOldAutoOnesArePruned() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
    let vault = tmp.appendingPathComponent("Notas")
    let backups = tmp.appendingPathComponent("Copias")
    try FileManager.default.createDirectory(at: vault.appendingPathComponent("Cambio físico"), withIntermediateDirectories: true)
    try "---\nobjetivo_peso_kg: 90\n---\n| Fecha | Peso |\n|--|--|\n| 01/01/2026 | 100 |\n".write(to: vault.appendingPathComponent("Cambio físico/Peso.md"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
    // 20 copias automáticas viejas, una manual y una carpeta ajena
    for d in 1...20 { try FileManager.default.createDirectory(at: backups.appendingPathComponent(String(format: "Notas-auto-2026-09-%02d", d)), withIntermediateDirectories: true) }
    try FileManager.default.createDirectory(at: backups.appendingPathComponent("Notas-manual-2026-01-01-1200"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: backups.appendingPathComponent("otra-cosa"), withIntermediateDirectories: true)

    let store = Store(root: vault, backups: backups)
    store.addWeight(date: DayKey.date("2026-02-01")!, kg: 99, note: "")
    let names = Set(store.allBackups().map(\.lastPathComponent))
    #expect(store.autoBackups().count == Store.keepAutoBackups)           // 14 automáticas
    #expect(names.contains("Notas-manual-2026-01-01-1200") && names.contains("otra-cosa"))
    #expect(!names.contains("Notas-auto-2026-09-01") && names.contains("Notas-auto-2026-09-20"))
    #expect(store.autoBackups().contains { $0.lastPathComponent.hasPrefix("Notas-auto-2026-1") || $0.lastPathComponent.contains(DayKey.string(Date())) })
    // la copia de hoy tiene el contenido de antes del cambio
    let today = try #require(store.autoBackups().first { $0.lastPathComponent.hasSuffix(DayKey.string(Date())) })
    #expect(try String(contentsOf: today.appendingPathComponent("Cambio físico/Peso.md"), encoding: .utf8).contains("| 01/01/2026 | 100 |"))
    #expect(!(try String(contentsOf: today.appendingPathComponent("Cambio físico/Peso.md"), encoding: .utf8)).contains("99"))
    let manual = try #require(store.backupNow())
    #expect(manual.lastPathComponent.contains("-manual-") && manual.deletingLastPathComponent().resolvingSymlinksInPath().path == backups.resolvingSymlinksInPath().path)
}


@Test func relatedLinks() throws {
    let a = try #require(Edit.addRelated("# Nota\ntexto", links: ["Peso", "Casa"]))
    #expect(a == "# Nota\ntexto\n\n---\nRelacionado: [[Peso]] · [[Casa]]\n")
    let b = try #require(Edit.addRelated(a, links: ["Casa", "Nala"]))      // no repite Casa
    #expect(b.hasSuffix("Relacionado: [[Peso]] · [[Casa]] · [[Nala]]\n"))
    let c = try #require(Edit.addRelated("# X\n\n---\n[[Inbox]]\n", links: ["Peso"]))   // extiende el pie de enlaces
    #expect(c == "# X\n\n---\n[[Inbox]] · [[Peso]]\n")
    let d = try #require(Edit.addRelated("# X\n---\n", links: ["Peso"]))
    #expect(d == "# X\n---\nRelacionado: [[Peso]]\n")
    #expect(Edit.addRelated("ver [[Peso]]", links: ["peso"]) == "ver [[Peso]]")
}

@MainActor @Test func weeksAndDiaryGetConnectedOnCopy() throws {
    guard let path = ProcessInfo.processInfo.environment["VAULT_COPY"] else { return }
    let store = Store(root: try tempVaultCopy(path))
    store.createReview(key: "2026-W44", monday: DayKey.date("2026-10-26")!)
    let w44 = store.read(store.reviewFile("2026-W44"))
    #expect(w44.contains("[[Revisión semanal 2026-W43]]") && w44.contains("[[Revisión mensual 2026-10]]"))
    #expect(store.read(store.reviewFile("2026-W43")).contains("[[Revisión semanal 2026-W44]]"))
    #expect(store.read(store.monthReviewFile("2026-10")).contains("[[Revisión semanal 2026-W44]]"))
    store.appendToDiary(DayKey.date("2026-10-27")!, text: "hola")
    #expect(store.read(Store.diaryPath(DayKey.date("2026-10-27")!)).contains("[[Revisión semanal 2026-W44]]"))
    print("AISLADAS", store.isolatedNotes().map(\.name))
}
