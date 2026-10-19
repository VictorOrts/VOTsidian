import Charts
import SwiftUI

enum LabStatus: String {
    case low, ok, high, unknown
    var label: String { switch self { case .low: "Bajo"; case .ok: "Normal"; case .high: "Alto"; case .unknown: "Sin referencia" } }
    var color: Color { switch self { case .low, .high: Brand.warn; case .ok: Brand.accent; case .unknown: .gray } }
    var outOfRange: Bool { self == .low || self == .high }
}

struct LabResult: Identifiable, Equatable {
    var date: Date
    var name: String
    var value: Double?
    var rawValue: String
    var unit: String
    var refMin: Double?
    var refMax: Double?
    var override: String
    var note: String
    var line: Int
    var id: Int { line }

    /// Con referencia manda la referencia; sin ella vale lo que se escribió en «Estado».
    var status: LabStatus {
        guard let v = value else { return .unknown }
        if let lo = refMin, v < lo { return .low }
        if let hi = refMax, v > hi { return .high }
        if refMin != nil || refMax != nil { return .ok }
        let o = MD.fold(override)
        return o.contains("bajo") ? .low : o.contains("alto") ? .high : o.contains("normal") ? .ok : .unknown
    }

    var refText: String {
        switch (refMin, refMax) {
        case let (lo?, hi?): return "\(MD.formatNumber(lo, comma: true))–\(MD.formatNumber(hi, comma: true))"
        case let (nil, hi?): return "≤\(MD.formatNumber(hi, comma: true))"
        case let (lo?, nil): return "≥\(MD.formatNumber(lo, comma: true))"
        default: return ""
        }
    }

    var valueText: String { (value.map { MD.formatNumber($0, comma: true) } ?? rawValue) + (unit.isEmpty ? "" : " \(unit)") }
}

/// Un parámetro (glucosa, HDL…) con todos sus resultados en el tiempo.
struct LabParameter: Identifiable {
    var name: String
    var results: [LabResult]     // de más antiguo a más reciente
    var latest: LabResult
    var id: String { MD.fold(name) }
    var previous: LabResult? { results.count > 1 ? results[results.count - 2] : nil }

    /// Nil si no hay resultados: un parámetro sin valores no existe.
    init?(name: String, results: [LabResult]) {
        guard let last = results.last else { return nil }
        self.name = name
        self.results = results
        self.latest = last
    }
}

struct LabRowInput: Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var value = ""
    var unit = ""
    var refMin = ""
    var refMax = ""
    var estado = ""
}

enum Labs {
    static let file = "Organización/Médico/Analíticas.md"

    static let suggestedNames = ["Glucosa", "HbA1c", "Insulina", "Colesterol total", "HDL", "LDL", "Triglicéridos", "Creatinina", "Urea", "Ácido úrico",
                                 "GOT (AST)", "GPT (ALT)", "GGT", "CK", "TSH", "Vitamina D", "Vitamina B12", "Ferritina", "Hemoglobina", "Creatinina en orina"]

    static var template: String {
        """
        ---
        tipo: analiticas
        tags:
          - salud
          - analiticas
        ---

        # Analíticas

        > Un valor por fila. Si no pones referencia, puedes indicar en «Estado» si el resultado es bajo, normal o alto. Los rangos de referencia los marca tu laboratorio.

        | Fecha | Valor | Resultado | Unidad | Ref. mín | Ref. máx | Estado | Notas |
        | :---- | :---- | --------: | :----- | -------: | -------: | :----- | :---- |

        ---
        [[Médico]]
        """
    }

    /// Valores que ya tenías anotados en la nota Médico (análisis del 18/09/2026).
    static let seed: [(name: String, value: String, unit: String, min: String, max: String, estado: String, note: String)] = [
        ("HbA1c", "5,5", "%", "", "", "normal", "Resultado normal según tu nota Médico"),
        ("HDL", "29", "mg/dl", "", "", "bajo", "HDL bajo según tu nota Médico"),
        ("CK", "224", "U/l", "", "170", "", "Posible efecto del entrenamiento"),
        ("Creatinina en orina", "187,8", "mg/dl", "63", "166", "", "Se explica por el deporte"),
    ]

    static func table(_ text: String) -> NamedTable? {
        Parse.tables(text).first { $0.col("valor") != nil && $0.col("resultado") != nil }
    }

    static func parse(_ text: String) -> [LabResult] {
        guard let t = table(text) else { return [] }
        return t.rows.compactMap { r in
            let name = t.value(r, "valor")
            guard !name.isEmpty, let d = DayKey.dmyDate(r.cells.first ?? "") ?? DayKey.date(r.cells.first ?? "") else { return nil }
            let raw = t.value(r, "resultado")
            return LabResult(date: d, name: name, value: raw.isEmpty ? nil : MD.number(raw), rawValue: raw, unit: t.value(r, "unidad"),
                             refMin: MD.number(t.value(r, "min")).flatMap { t.value(r, "min").isEmpty ? nil : $0 },
                             refMax: MD.number(t.value(r, "max")).flatMap { t.value(r, "max").isEmpty ? nil : $0 },
                             override: t.value(r, "estado"), note: t.value(r, "notas"), line: r.line)
        }
    }

    static func parameters(_ results: [LabResult]) -> [LabParameter] {
        Dictionary(grouping: results, by: { MD.fold($0.name) }).values
            .compactMap { group in
                LabParameter(name: group.last?.name ?? "", results: group.sorted { ($0.date, $0.line) < ($1.date, $1.line) })
            }
            .sorted { MD.fold($0.name) < MD.fold($1.name) }
    }
}

extension Edit {
    /// Inserta varias filas seguidas detrás de `afterLine`.
    static func insertTableRows(_ text: String, afterLine: Int, rows: [[String]]) -> String? {
        var lines = MD.lines(text)
        guard afterLine >= 0, afterLine < lines.count, MD.isTable(lines[afterLine]), !rows.isEmpty else { return nil }
        lines.insert(contentsOf: rows.map(rowString), at: afterLine + 1)
        return lines.joined(separator: "\n")
    }
}

extension Store {
    var labParameters: [LabParameter] { Labs.parameters(labs) }
    var labsExist: Bool { FileManager.default.fileExists(atPath: url(Labs.file).path) }

    /// Último resultado de cada parámetro que está fuera de rango.
    var labsOutOfRange: [LabResult] { labParameters.map(\.latest).filter { $0.status.outOfRange } }

    func ensureLabs() { if !labsExist { writeNote(Labs.file, text: Labs.template) } }

    /// Añade a la tabla los resultados de una analítica (todos en un solo cambio).
    func addLabResults(date: Date, rows: [LabRowInput]) {
        let valid = rows.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !valid.isEmpty else { return }
        ensureLabs()
        edit(Labs.file) { text in
            guard let t = Labs.table(text) else { return nil }
            func put(_ cells: inout [String], _ col: String, _ v: String) { if let i = t.col(col), i < cells.count { cells[i] = v } }
            let new: [[String]] = valid.map { r in
                var c = [String](repeating: "", count: t.header.count)
                c[0] = DayKey.dmy(date)
                put(&c, "valor", r.name.trimmingCharacters(in: .whitespaces)); put(&c, "resultado", r.value.trimmingCharacters(in: .whitespaces))
                put(&c, "unidad", r.unit); put(&c, "min", r.refMin); put(&c, "max", r.refMax); put(&c, "estado", r.estado)
                return c
            }
            return Edit.insertTableRows(text, afterLine: t.lastLine, rows: new)
        }
    }

    func addSeedLabs() {
        guard let date = DayKey.dmyDate("18/09/2026") else { return }
        ensureLabs()
        edit(Labs.file) { text in
            guard let t = Labs.table(text) else { return nil }
            let existing = Set(Labs.parse(text).map { MD.fold($0.name) + DayKey.string($0.date) })
            let rows: [[String]] = Labs.seed.compactMap { s in
                guard !existing.contains(MD.fold(s.name) + DayKey.string(date)) else { return nil }
                var c = [String](repeating: "", count: t.header.count)
                func put(_ col: String, _ v: String) { if let i = t.col(col) { c[i] = v } }
                c[0] = DayKey.dmy(date); put("valor", s.name); put("resultado", s.value); put("unidad", s.unit)
                put("min", s.min); put("max", s.max); put("estado", s.estado); put("notas", s.note)
                return c
            }
            return Edit.insertTableRows(text, afterLine: t.lastLine, rows: rows)
        }
    }
}
