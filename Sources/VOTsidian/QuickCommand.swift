import Foundation

/// Órdenes cortas que se escriben en ⌘K: «peso 105,5», «ánimo 4», «dormí 7,5 ayer», «pinchazo hoy», «compra leche, huevos»…
enum QuickCommand: Equatable {
    case weight(Double, Date)
    case mood(Int, Date)
    case sleep(Double, Date)
    case injection(Date)
    case task(String, Date?, String?, Int)       // texto, fecha, repetición, prioridad
    case idea(String)
    case diary(String)
    case appointment(String, Date)
    case measure(String, Double, Date)
    case shopping([String])

    /// Lo que va a hacer, para enseñarlo antes de ejecutarlo.
    var summary: String {
        func day(_ d: Date) -> String { d == DayKey.today() ? "hoy" : shortDate(d) }
        switch self {
        case .weight(let kg, let d): return "Registrar peso \(MD.formatNumber(kg, comma: true)) kg (\(day(d)))"
        case .mood(let n, let d): return "Anotar ánimo \(n) de 5 (\(day(d)))"
        case .sleep(let h, let d): return "Anotar sueño \(MD.formatNumber(h, comma: true)) h (\(day(d)))"
        case .injection(let d): return "Registrar pinchazo de Mounjaro (\(day(d)))"
        case .task(let t, let d, let r, let p):
            return "Tarea «\(t)»" + (d.map { " para \(day($0))" } ?? "") + (r.map { " · \(Recurrence.describe($0))" } ?? "") + (p == 3 ? " · urgente" : "")
        case .idea(let t): return "Guardar idea «\(t)»"
        case .diary(let t): return "Añadir a la nota de hoy: «\(t)»"
        case .appointment(let t, let d): return "Cita «\(t)» el \(day(d))"
        case .measure(let f, let v, let d): return "Medida de \(f.lowercased()): \(MD.formatNumber(v, comma: true)) (\(day(d)))"
        case .shopping(let items): return "Añadir a la compra: \(items.joined(separator: ", "))"
        }
    }

    private static let measureFields = ["cintura": "Cintura", "cadera": "Cadera", "pecho": "Pecho", "brazo": "Brazo", "muslo": "Muslo", "grasa": "Grasa"]

    static func parse(_ raw: String, today: Date = DayKey.today()) -> QuickCommand? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let space = text.firstIndex(of: " ") else {
            // órdenes sin argumento
            switch MD.fold(text) {
            case "pinchazo", "pinche", "inyeccion": return .injection(today)
            default: return nil
            }
        }
        let verb = MD.fold(String(text[..<space]))
        let arg = String(text[text.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        guard !arg.isEmpty else { return nil }

        /// Primer número del argumento (admite coma decimal) y el resto como posible fecha.
        func numberAndDate() -> (Double, Date)? {
            let parts = arg.split(separator: " ", maxSplits: 1).map(String.init)
            guard let first = parts.first, first.range(of: #"^\d+([.,]\d+)?$"#, options: .regularExpression) != nil, let n = MD.number(first) else { return nil }
            let rest = parts.count > 1 ? parts[1] : ""
            let d = rest.isEmpty ? today : (NaturalDate.extract(rest, today: today).date ?? today)
            return (n, d)
        }

        switch verb {
        case "peso", "pese", "kg":
            guard let (kg, d) = numberAndDate(), (30...400).contains(kg) else { return nil }
            return .weight(kg, d)
        case "animo", "humor":
            guard let (n, d) = numberAndDate(), n == n.rounded(), (1...5).contains(Int(n)) else { return nil }
            return .mood(Int(n), d)
        case "sueno", "dormi", "dormido":
            guard let (h, d) = numberAndDate(), h > 0, h <= 16 else { return nil }
            return .sleep(h, d)
        case "pinchazo", "pinche", "inyeccion":
            let p = NaturalDate.extract(arg, today: today)
            guard p.text.isEmpty || MD.fold(p.text) == "hoy" else { return nil }
            return .injection(p.date ?? today)
        case "tarea", "t", "todo", "recordar", "recuerdame":
            let p = NaturalDate.extractTask(arg, today: today)
            guard !p.text.isEmpty else { return nil }
            return .task(p.text, p.date, p.recurrence, p.priority)
        case "idea": return .idea(arg)
        case "nota", "diario", "apunta", "apunte": return .diary(arg)
        case "cita", "medico":
            let p = NaturalDate.extract(arg, today: today)
            guard !p.text.isEmpty else { return nil }
            return .appointment(p.text, p.date ?? today)
        case "compra", "comprar", "lista":
            let items = arg.replacingOccurrences(of: " y ", with: ",").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return items.isEmpty ? nil : .shopping(items)
        default:
            if let field = measureFields[verb], let (v, d) = numberAndDate(), v > 0 { return .measure(field, v, d) }
            return nil
        }
    }
}

// MARK: - Lista de la compra

struct ShoppingItem: Identifiable, Equatable {
    var line: Int
    var raw: String
    var text: String
    var done: Bool
    var category: String
    var id: Int { line }
}

enum Shopping {
    static let file = "Cambio físico/Lista de la compra.md"
    static let defaultCategories = ["Proteína", "Carbohidratos", "Verdura y fruta", "Grasas", "Otros"]

    static var template: String {
        "---\ntipo: compra\ntags:\n  - compra\n---\n\n# Lista de la compra\n\n> Se marca al comprar. «Vaciar comprados» quita lo que ya tienes.\n\n"
            + defaultCategories.map { "## \($0)\n" }.joined(separator: "\n") + "\n---\n[[Menú y compra]] · [[Plan Nutricional]]\n"
    }

    static func parse(_ text: String) -> [ShoppingItem] {
        let lines = MD.lines(text)
        let fence = MD.fenced(lines)
        var category = "Otros"
        var out: [ShoppingItem] = []
        for (i, l) in lines.enumerated() where !fence.contains(i) {
            if l.hasPrefix("## ") { category = String(l.dropFirst(3)).trimmingCharacters(in: .whitespaces); continue }
            guard let m = l.firstMatch(of: /^- \[([ xX])\] (.+)$/) else { continue }
            let t = String(m.2).replacingOccurrences(of: #"\s*\[completion::[^\]]*\]"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.append(ShoppingItem(line: i, raw: l, text: t, done: m.1 != " ", category: category)) }
        }
        return out
    }

    /// Añade artículos bajo una categoría (la crea si falta) sin repetir los que ya están. Devuelve el texto y cuántos añadió.
    static func addItems(_ text: String, items: [String], category: String) -> (text: String, added: Int) {
        var lines = MD.lines(text)
        let existing = Set(parse(text).map { MD.fold($0.text) })
        var fresh: [String] = []
        for i in items {
            let t = i.trimmingCharacters(in: .whitespaces)
            let cap = t.prefix(1).uppercased() + t.dropFirst()
            if !t.isEmpty, !existing.contains(MD.fold(t)), !fresh.contains(where: { MD.fold($0) == MD.fold(t) }) { fresh.append(cap) }
        }
        guard !fresh.isEmpty else { return (text, 0) }
        let new = fresh.map { "- [ ] \($0)" }
        if let r = MD.section(lines, containing: category), let head = (0..<lines.count).first(where: { lines[$0].hasPrefix("## ") && MD.fold(lines[$0]).contains(MD.fold(category)) }) {
            let last = r.last(where: { lines[$0].hasPrefix("- [") }) ?? head
            lines.insert(contentsOf: new, at: last + 1)
        } else {
            // sección nueva antes del pie
            var at = lines.count
            if let hr = lines.lastIndex(of: "---"), hr > 0 { at = hr }
            lines.insert(contentsOf: ["## \(category)"] + new + [""], at: at)
        }
        return (lines.joined(separator: "\n"), fresh.count)
    }

    static func clearDone(_ text: String) -> String {
        let lines = MD.lines(text)
        let fence = MD.fenced(lines)
        return lines.enumerated().filter { i, l in fence.contains(i) || l.range(of: #"^- \[[xX]\] "#, options: .regularExpression) == nil }.map(\.element).joined(separator: "\n")
    }

    static func uncheckAll(_ text: String) -> String {
        MD.lines(text).map { $0.range(of: #"^- \[[xX]\] "#, options: .regularExpression) != nil ? "- [ ] " + $0.dropFirst(6) : $0 }.joined(separator: "\n")
    }

    /// Categorías y artículos de la sección «Lista de la compra» de la nota Menú y compra (`- **Proteína:** pollo, pavo…`).
    static func fromMenu(_ menu: String) -> [(category: String, items: [String])] {
        let lines = MD.lines(menu)
        guard let r = MD.section(lines, containing: "Lista de la compra") else { return [] }
        return r.compactMap { i in
            guard let m = lines[i].firstMatch(of: /^- \*\*([^*:]+):\*\*\s*(.+)$/) else { return nil }
            let items = String(m.2).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ";", with: ",")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return items.isEmpty ? nil : (String(m.1).trimmingCharacters(in: .whitespaces), items)
        }
    }
}
