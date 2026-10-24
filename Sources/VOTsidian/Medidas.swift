import Foundation

// MARK: - Medidas corporales

struct MeasureRecord: Identifiable, Equatable {
    var date: Date
    var values: [String: Double]
    var note: String
    var line: Int
    var id: Int { line }
}

enum Measures {
    static var file: String { VaultPath.medidas }
    static let fields = ["Cintura", "Cadera", "Pecho", "Brazo", "Muslo", "Grasa"]
    static let units = ["Cintura": "cm", "Cadera": "cm", "Pecho": "cm", "Brazo": "cm", "Muslo": "cm", "Grasa": "%"]

    static func parse(_ text: String) -> (table: NamedTable?, records: [MeasureRecord]) {
        guard let t = Parse.tables(text).first(where: { $0.col("cintura") != nil }) else { return (nil, []) }
        let recs = t.rows.compactMap { r -> MeasureRecord? in
            guard let d = DayKey.dmyDate(r.cells.first ?? "") ?? DayKey.date(r.cells.first ?? "") else { return nil }
            var v: [String: Double] = [:]
            for f in fields { if let n = MD.number(t.value(r, f)), !t.value(r, f).isEmpty { v[f] = n } }
            return MeasureRecord(date: d, values: v, note: t.value(r, "notas"), line: r.line)
        }.sorted { $0.date < $1.date }
        return (t, recs)
    }

    static var template: String {
        """
        ---
        tipo: medidas
        tags:
          - salud
          - medidas
        ---

        # Medidas corporales

        > Mídete una vez al mes, en ayunas y con la cinta sin apretar, en los mismos puntos.

        | Fecha | Cintura (cm) | Cadera (cm) | Pecho (cm) | Brazo (cm) | Muslo (cm) | Grasa (%) | Notas |
        | :---- | -----------: | ----------: | ---------: | ---------: | ---------: | --------: | :---- |

        ---
        [[Peso]]
        """
    }
}


// MARK: - Etiquetas, resumen y menciones (estilo Bear / Obsidian)

enum NoteInfo {
    /// Etiquetas de una nota: la lista `tags:` del encabezado y los `#etiqueta` del texto (fuera de código).
    static func tags(_ text: String) -> [String] {
        var out: [String] = MD.frontmatterList(text, key: "tags").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#\"' ")) }
        let lines = MD.lines(text)
        let fence = MD.fenced(lines)
        var start = 0
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") { start = end + 1 }
        for (i, l) in lines.enumerated() where i >= start && !fence.contains(i) && l.utf8.contains(UInt8(ascii: "#")) {
            for m in l.matches(of: /(?:^|\s)#([\p{L}][\p{L}\p{N}_\/-]*)/) { out.append(String(m.1)) }
        }
        var seen = Set<String>()
        return out.filter { !$0.isEmpty && seen.insert(MD.fold($0)).inserted }
    }

    /// Primera línea con texto (sin encabezados, listas ni formato) para mostrar como vista previa.
    static func snippet(_ text: String) -> String {
        let lines = MD.lines(text)
        let fence = MD.fenced(lines)
        var start = 0
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") { start = end + 1 }
        for (i, raw) in lines.enumerated() where i >= start && !fence.contains(i) {
            var l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("#") || l.hasPrefix("|") || l == "---" { continue }
            l = l.replacingOccurrences(of: #"^(>\s*(\[![^\]]*\]\s*)?|[-*]\s+(\[[ xX]\]\s+)?|\d+\.\s+)"#, with: "", options: .regularExpression)
            l = l.replacingOccurrences(of: #"\[\[([^\]|]*\|)?([^\]]*)\]\]"#, with: "$2", options: .regularExpression)
                .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            if !l.isEmpty { return String(l.prefix(120)) }
        }
        return ""
    }

    static func wordCount(_ text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.count
    }

    static func aliases(_ text: String) -> [String] { MD.frontmatterList(text, key: "aliases") }
}
