import Foundation

extension MD {
    /// Índice de la línea `raw`: el `hint` si sigue ahí; si no, la coincidencia más cercana a él.
    /// Con líneas idénticas (dos «- [ ] Comprar pan») evita tocar la que no era.
    static func index(of raw: String, in lines: [String], near hint: Int) -> Int? {
        if hint >= 0, hint < lines.count, lines[hint] == raw { return hint }
        return lines.indices.filter { lines[$0] == raw }.min { abs($0 - hint) < abs($1 - hint) }
    }
}

enum DayKey {
    static func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        return cal
    }

    static func string(_ date: Date) -> String {
        let c = calendar().dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func dmy(_ date: Date) -> String {
        let c = calendar().dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d/%02d/%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
    }

    /// Fecha ISO `2026-10-18`.
    static func date(_ text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let p = t.split(separator: "-").compactMap { Int($0) }
        return make(p[0], p[1], p[2])
    }

    /// Fecha `18/10/2026`.
    static func dmyDate(_ text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.range(of: #"^\d{1,2}/\d{1,2}/\d{4}$"#, options: .regularExpression) != nil else { return nil }
        let p = t.split(separator: "/").compactMap { Int($0) }
        return make(p[2], p[1], p[0])
    }

    /// Fecha exacta o `nil` si no existe: el calendario convierte 31/02 en 3 de marzo sin avisar, y eso no se quiere.
    static func make(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        let cal = calendar()
        guard let d = cal.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return c.year == year && c.month == month && c.day == day ? d : nil
    }

    static func today() -> Date { calendar().startOfDay(for: Date()) }

    static func days(from a: Date, to b: Date) -> Int {
        calendar().dateComponents([.day], from: calendar().startOfDay(for: a), to: calendar().startOfDay(for: b)).day ?? 0
    }

    static func adding(days: Int, to d: Date) -> Date { calendar().date(byAdding: .day, value: days, to: d)! }

    static func weekKey(_ date: Date) -> String {
        let cal = Calendar(identifier: .iso8601)
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    static func weekStart(_ date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: date)!.start
    }

    static func esLong(_ date: Date, _ format: Date.FormatStyle) -> String {
        date.formatted(format.locale(Locale(identifier: "es")))
    }
}

enum MD {
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Líneas sin el salto. Los archivos con saltos de Windows (`\r\n`) se leen igual; al editarlos quedan con `\n`.
    static func lines(_ text: String) -> [String] {
        (text.contains("\r\n") ? text.replacingOccurrences(of: "\r\n", with: "\n") : text).components(separatedBy: "\n")
    }

    static func frontmatter(_ text: String) -> [String: String] {
        let l = lines(text)
        guard l.first == "---", let end = l.dropFirst().firstIndex(of: "---") else { return [:] }
        var out: [String: String] = [:]
        for line in l[1..<end] {
            guard !line.hasPrefix(" "), !line.hasPrefix("-"), let i = line.firstIndex(of: ":") else { continue }
            var v = String(line[line.index(after: i)...]).trimmingCharacters(in: .whitespaces)
            if v.count >= 2, v.hasPrefix("\""), v.hasSuffix("\"") {
                v = String(v.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
            } else if v.count >= 2, v.hasPrefix("'"), v.hasSuffix("'") {
                v = String(v.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }
            out[String(line[..<i]).trimmingCharacters(in: .whitespaces)] = v
        }
        return out
    }

    static func frontmatterList(_ text: String, key: String) -> [String] {
        let l = lines(text)
        guard l.first == "---", let end = l.dropFirst().firstIndex(of: "---"),
              let start = l[1..<end].firstIndex(where: { $0.hasPrefix("\(key):") }) else { return [] }
        var out: [String] = []
        for line in l[(start + 1)..<end] {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("- ") else { break }
            out.append(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }
        return out
    }

    static func cells(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.replacingOccurrences(of: "\\|", with: "\u{1}").components(separatedBy: "|")
            .map { $0.replacingOccurrences(of: "\u{1}", with: "|").trimmingCharacters(in: .whitespaces) }
    }

    static func isTable(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).hasPrefix("|") }

    /// Índices de línea que están dentro de un bloque de código.
    static func fenced(_ lines: [String]) -> Set<Int> {
        var out = Set<Int>()
        var inside = false
        for (i, l) in lines.enumerated() {
            if l.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inside.toggle(); out.insert(i); continue }
            if inside { out.insert(i) }
        }
        return out
    }

    /// Filas de tabla fuera de bloques de código.
    static func tableRows(_ lines: [String]) -> [(index: Int, cells: [String])] {
        let fence = fenced(lines)
        return lines.enumerated().compactMap { i, l in
            isTable(l) && !fence.contains(i) ? (i, cells(l)) : nil
        }
    }

    /// Línea del encabezado de la tabla que contiene `line`.
    static func tableHeaderLine(_ lines: [String], containing line: Int) -> Int {
        var h = line
        while h > 0, isTable(lines[h - 1]) { h -= 1 }
        return h
    }

    static func number(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: ".")
        guard let m = t.firstMatch(of: /-?\d+(\.\d+)?/) else { return nil }
        return Double(String(m.0))
    }

    /// Líneas tras un encabezado (que contiene `title`) hasta el siguiente encabezado.
    static func section(_ lines: [String], containing title: String) -> Range<Int>? {
        let fence = fenced(lines)
        let key = fold(title)
        guard let i = lines.indices.first(where: { !fence.contains($0) && lines[$0].hasPrefix("#") && fold(lines[$0]).contains(key) }) else { return nil }
        var j = i + 1
        while j < lines.count, fence.contains(j) || !lines[j].hasPrefix("#") { j += 1 }
        return (i + 1)..<j
    }

    /// Cambia el contenido de la columna `col` (0 = primera) conservando el ancho de la celda.
    static func setCell(_ line: String, col: Int, value: String) -> String {
        var parts = line.components(separatedBy: "|")
        let idx = col + 1
        guard idx < parts.count - 1 else { return line }
        let width = parts[idx].count
        let content = value
        if width >= content.count + 2 {
            let total = width - content.count
            let left = total / 2
            parts[idx] = String(repeating: " ", count: left) + content + String(repeating: " ", count: total - left)
        } else {
            parts[idx] = " \(content) "
        }
        return parts.joined(separator: "|")
    }

    static func formatNumber(_ v: Double, comma: Bool = false) -> String {
        let s = String(format: "%g", v)
        return comma ? s.replacingOccurrences(of: ".", with: ",") : s
    }
}
