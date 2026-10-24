import Foundation

extension Array {
    /// Inserta sin salirse de los límites: una tabla que es solo la cabecera, al final del archivo, o una línea que ya no está,
    /// no debe cerrar la app.
    mutating func insertClamped(_ element: Element, at index: Int) { insert(element, at: Swift.min(Swift.max(index, 0), count)) }
    mutating func insertClamped(contentsOf elements: [Element], at index: Int) { insert(contentsOf: elements, at: Swift.min(Swift.max(index, 0), count)) }
}

extension MD {
    /// Índice de la línea `raw`: el `hint` si sigue ahí; si no, la coincidencia más cercana a él.
    /// Con líneas idénticas (dos «- [ ] Comprar pan») evita tocar la que no era.
    static func index(of raw: String, in lines: [String], near hint: Int) -> Int? {
        if hint >= 0, hint < lines.count, lines[hint] == raw { return hint }
        return lines.indices.filter { lines[$0] == raw }.min { abs($0 - hint) < abs($1 - hint) }
    }
}

/// Hora del día en minutos desde medianoche, como se escribe en las notas («17:30»).
enum TimeOfDay {
    static func text(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    static func parse(_ s: String) -> Int? {
        guard let m = s.trimmingCharacters(in: .whitespaces).firstMatch(of: /^([0-9]{1,2})[:.]([0-9]{2})$/),
              let h = Int(m.1), let mi = Int(m.2), h < 24, mi < 60 else { return nil }
        return h * 60 + mi
    }

    /// La hora de una fecha (de un selector de hora).
    static func minutes(of date: Date) -> Int {
        let c = DayKey.calendar().dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Una fecha con esa hora, para enseñarla en un selector.
    static func date(_ minutes: Int, on day: Date = Date()) -> Date {
        DayKey.calendar().date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }
}

/// Lo que dura una tarea, en minutos, como se escribe en las notas: `⏱ 45m`, `⏱ 2h`, `⏱ 1h30m`.
enum TaskDuration {
    /// Hasta un día entero: lo demás es un error al escribir.
    static let range = 5...(24 * 60)

    static func text(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h == 0 ? "\(m)m" : m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }

    /// Las duraciones de los menús, con `current` si no es una de ellas (para no perderla al editar).
    static func presets(including current: Int = 0) -> [Int] {
        let base = [15, 30, 45, 60, 90, 120, 180, 240]
        return current > 0 && !base.contains(current) ? (base + [current]).sorted() : base
    }

    /// «1 h 30 min», para leerlo en pantalla.
    static func human(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h == 0 ? "\(m) min" : m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// El marcador en una línea de tarea. Con o sin el selector de variación (⏱️), que añaden algunos teclados de emoji.
    static let pattern = #"⏱\x{FE0F}?\s*(?:[0-9]{1,2}h(?:[0-9]{1,2}m?)?|[0-9]{1,4}m(?:in)?)"#

    /// La duración marcada en una línea. Con `NSString`: la búsqueda de `String` no devuelve nada si el emoji lleva el selector
    /// de variación, porque el resultado no cae en el borde de una letra.
    static func find(in line: String) -> Int? {
        let ns = line as NSString
        let r = ns.range(of: pattern, options: .regularExpression)
        guard r.location != NSNotFound else { return nil }
        return parse(ns.substring(with: r).drop { !$0.isASCII || !$0.isNumber })
    }

    /// «45m», «2h», «1h30m», «1h30», «90min».
    static func parse<S: StringProtocol>(_ s: S) -> Int? {
        let s = String(s)
        guard let m = s.trimmingCharacters(in: .whitespaces).firstMatch(of: /^(?:([0-9]{1,2})\s*h)?\s*(?:([0-9]{1,4})\s*(?:m|min)?)?$/) else { return nil }
        let h = m.1.flatMap { Int($0) }, mi = m.2.flatMap { Int($0) }
        guard h != nil || mi != nil else { return nil }
        // «90» sin unidad solo vale detrás de las horas («1h30»); suelto podría ser cualquier cosa.
        if h == nil, !s.contains("m") { return nil }
        let total = (h ?? 0) * 60 + (mi ?? 0)
        return range.contains(total) ? total : nil
    }
}

enum DayKey {
    /// Se crea una vez: se pide en cada fecha que se analiza o se pinta. La zona horaria sigue a la del sistema.
    private static let shared: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = .autoupdatingCurrent
        return cal
    }()

    static func calendar() -> Calendar { shared }

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
        // [0-9] y no \d: «\d» acepta también cifras de otros alfabetos, que `Int` no entiende.
        guard t.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { return nil }
        let p = t.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return make(p[0], p[1], p[2])
    }

    /// Fecha `18/10/2026`.
    static func dmyDate(_ text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.range(of: #"^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$"#, options: .regularExpression) != nil else { return nil }
        let p = t.split(separator: "/").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
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

    /// Con un número de días absurdo, el calendario no da fecha: se suman los segundos a mano en vez de cerrar la app.
    static func adding(days: Int, to d: Date) -> Date { calendar().date(byAdding: .day, value: days, to: d) ?? d.addingTimeInterval(Double(days) * 86_400) }

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

    /// `text.contains(part)` byte a byte, para textos ya plegados con `fold` (sin tildes ni mayúsculas, así que no hay
    /// letras compuestas que distinguir). `String.contains` va letra a letra y es ~30 veces más lento en notas largas.
    static func contains(_ text: String, _ part: String) -> Bool {
        var text = text, part = part
        return text.withUTF8 { a in part.withUTF8 { b in b.isEmpty || memmem(a.baseAddress, a.count, b.baseAddress, b.count) != nil } }
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

    /// Trozos de una fila separados por las `|` de verdad: un `\|` (como en `[[Nota\|alias]]`) se queda dentro de su celda.
    static func rawCells(_ line: String) -> [String] {
        line.replacingOccurrences(of: "\\|", with: "\u{1}").components(separatedBy: "|")
            .map { $0.replacingOccurrences(of: "\u{1}", with: "\\|") }
    }

    /// Escapa las `|` sueltas de un valor para que no partan la celda; las ya escapadas se dejan.
    static func escapeCell(_ value: String) -> String {
        value.replacingOccurrences(of: #"(?<!\\)\|"#, with: #"\\|"#, options: .regularExpression).replacingOccurrences(of: "\n", with: " ")
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

    /// Entero de un número escrito en una nota, o `nil` si es absurdo: convertir un `Double` enorme con `Int(_:)` cierra la app.
    static func int(_ v: Double?) -> Int? {
        guard let v, v.isFinite, abs(v) <= 1_000_000_000 else { return nil }
        return Int(v)
    }

    /// ¿Hay un «[[» en el texto? Recorre bytes: mucho más barato que una expresión regular, para descartar líneas sin enlaces.
    static func hasDoubleBracket(_ s: String) -> Bool {
        var previous: UInt8 = 0
        for b in s.utf8 {
            if b == 91, previous == 91 { return true }
            previous = b
        }
        return false
    }

    /// Primer número del texto. Entiende coma decimal («105,5») y separador de miles («1.234,5», «1.234.567», «1,234.5»).
    /// Solo cifras ASCII, recorriendo bytes: se llama en cada celda de cada tabla y una expresión regular era lo más caro.
    static func number(_ s: String) -> Double? {
        let b = Array(s.utf8)
        func isDigit(_ i: Int) -> Bool { i < b.count && b[i] >= 48 && b[i] <= 57 }
        var i = 0
        while i < b.count, !isDigit(i) { i += 1 }
        guard i < b.count else { return nil }
        let start = i > 0 && b[i - 1] == 45 ? i - 1 : i          // «-» justo delante
        var j = i
        while isDigit(j) { j += 1 }
        while j < b.count, b[j] == 46 || b[j] == 44, isDigit(j + 1) {   // «.» o «,» seguidos de cifras
            j += 1
            while isDigit(j) { j += 1 }
        }
        var t = String(decoding: b[start..<j], as: UTF8.self)
        let commas = t.filter { $0 == "," }.count, dots = t.filter { $0 == "." }.count
        if commas > 0, dots > 0 {
            // El separador que va último es el decimal; el otro, de miles.
            let decimal: Character = t.lastIndex(of: ",")! > t.lastIndex(of: ".")! ? "," : "."
            t = t.filter { $0 != (decimal == "," ? "." : ",") }.replacingOccurrences(of: ",", with: ".")
        } else if dots > 1 || commas > 1 {
            t = t.replacingOccurrences(of: dots > 1 ? "." : ",", with: "")
        } else {
            t = t.replacingOccurrences(of: ",", with: ".")
        }
        // Un número de cientos de cifras da infinito, que cierra la app al pasarlo a `Int` o a una gráfica.
        guard let v = Double(t), v.isFinite else { return nil }
        return v
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
        var parts = rawCells(line)
        let idx = col + 1
        guard idx < parts.count - 1 else { return line }
        let width = parts[idx].count
        let content = escapeCell(value)
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
