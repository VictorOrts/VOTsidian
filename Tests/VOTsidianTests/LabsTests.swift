import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Analíticas

@Test func labStatusAndParsing() throws {
    var text = Labs.template
    let table = try #require(Labs.table(text))
    func row(_ c: [String]) -> [String] { c }
    let rows = [
        row(["18/09/2026", "CK", "224", "U/l", "", "170", "", "Posible entrenamiento"]),
        row(["18/09/2026", "Creatinina en orina", "187,8", "mg/dl", "63", "166", "", ""]),
        row(["18/09/2026", "HDL", "29", "mg/dl", "", "", "bajo", ""]),
        row(["18/09/2026", "HbA1c", "5,5", "%", "", "", "", ""]),
        row(["18/09/2026", "Glucosa", "85", "mg/dl", "70", "99", "", ""]),
        row(["02/03/2026", "Glucosa", "62", "mg/dl", "70", "99", "", ""]),
        row(["18/09/2026", "Vitamina D", "30", "ng/ml", "30", "", "", ""]),
    ]
    text = try #require(Edit.insertTableRows(text, afterLine: table.lastLine, rows: rows))
    let r = Labs.parse(text)
    #expect(r.count == 7)
    func status(_ n: String, _ d: String = "18/09/2026") -> LabStatus? { r.first { $0.name == n && DayKey.dmy($0.date) == d }?.status }
    #expect(status("CK") == .high && status("Creatinina en orina") == .high && status("HDL") == .low)
    #expect(status("HbA1c") == .unknown && status("Glucosa") == .ok && status("Glucosa", "02/03/2026") == .low)
    #expect(status("Vitamina D") == .ok)                                  // justo en el límite inferior
    #expect(r.first { $0.name == "CK" }?.refText == "≤170" && r.first { $0.name == "Creatinina en orina" }?.refText == "63–166" && r.first { $0.name == "Vitamina D" }?.refText == "≥30")
    #expect(r.first { $0.name == "Creatinina en orina" }?.valueText == "187,8 mg/dl")
    let p = Labs.parameters(r)
    #expect(p.map(\.name) == ["CK", "Creatinina en orina", "Glucosa", "HbA1c", "HDL", "Vitamina D"])
    let glucosa = try #require(p.first { $0.name == "Glucosa" })
    #expect(glucosa.results.map { DayKey.dmy($0.date) } == ["02/03/2026", "18/09/2026"] && glucosa.latest.value == 85 && glucosa.previous?.value == 62)
}

@MainActor @Test func labsOnCopy() throws {
    guard let path = ProcessInfo.processInfo.environment["VAULT_COPY"] else { return }
    let store = Store(root: try tempVaultCopy(path))
    #expect(!store.labsExist && store.labs.isEmpty && store.labsOutOfRange.isEmpty)
    store.addSeedLabs()
    #expect(store.labsExist && store.labs.count == 4)
    store.addSeedLabs()                                                    // no se duplican
    #expect(store.labs.count == 4)
    let out = store.labsOutOfRange.map(\.name).sorted()
    #expect(out == ["CK", "Creatinina en orina", "HDL"])
    #expect(store.alerts().contains { $0.text.contains("Analítica: HDL bajo (29 mg/dl)") })
    // nueva analítica con varios valores a la vez
    var a = LabRowInput(); a.name = "CK"; a.value = "150"; a.unit = "U/l"; a.refMax = "170"
    var b = LabRowInput(); b.name = "Glucosa"; b.value = "88"; b.unit = "mg/dl"; b.refMin = "70"; b.refMax = "99"
    store.addLabResults(date: DayKey.date("2026-12-10")!, rows: [a, b, LabRowInput()])   // la fila vacía se ignora
    #expect(store.labs.count == 6)
    #expect(store.labsOutOfRange.map(\.name).sorted() == ["Creatinina en orina", "HDL"])    // CK ya está en rango en su último resultado
    store.undo()
    #expect(store.labs.count == 4 && store.labsOutOfRange.count == 3)                       // un solo paso para deshacer toda la analítica
    let summary = store.doctorSummary()
    #expect(summary.contains("ANALÍTICAS FUERA DE RANGO") && summary.contains("HDL: 29 mg/dl (bajo)") && summary.contains("CK: 224 U/l (alto, ref. ≤170)"))
    #expect(store.read(Labs.file).contains("[[Médico]]"))
    #expect(store.outLinks[Labs.file]?.contains("Organización/Médico/Médico.md") == true)   // queda conectada en el grafo
}
