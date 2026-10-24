import Foundation

/// Órdenes cortas que se escriben en ⌘K: «peso 105,5», «ánimo 4», «dormí 7,5 ayer», «pinchazo hoy», «compra leche, huevos»…
enum QuickCommand: Equatable {
    case weight(Double, Date)
    case mood(Int, Date)
    case sleep(Double, Date)
    case injection(Date)
    case task(String, Date?, String?, Int, Int?)       // texto, fecha, repetición, prioridad, hora
    case idea(String)
    case diary(String)
    case appointment(String, Date, Int?)               // texto, fecha, hora
    case measure(String, Double, Date)
    case shopping([String])
    case expense(ExpenseParser.Result)
    case book(String, String)                    // título, autor
    case finishBook(String)
    case loanPayment(String)

    /// Lo que va a hacer, para enseñarlo antes de ejecutarlo.
    var summary: String {
        func day(_ d: Date) -> String { d == DayKey.today() ? "hoy" : shortDate(d) }
        switch self {
        case .weight(let kg, let d): return "Registrar peso \(MD.formatNumber(kg, comma: true)) kg (\(day(d)))"
        case .mood(let n, let d): return "Anotar ánimo \(n) de 5 (\(day(d)))"
        case .sleep(let h, let d): return "Anotar sueño \(MD.formatNumber(h, comma: true)) h (\(day(d)))"
        case .injection(let d): return "Registrar pinchazo o toma (\(day(d)))"
        case .task(let t, let d, let r, let p, let h):
            return "Tarea «\(t)»" + (d.map { " para \(day($0))" } ?? "") + (h.map { " a las \(TimeOfDay.text($0))" } ?? "") + (r.map { " · \(Recurrence.describe($0))" } ?? "") + (p == 3 ? " · urgente" : "")
        case .idea(let t): return "Guardar idea «\(t)»"
        case .diary(let t): return "Añadir a la nota de hoy: «\(t)»"
        case .appointment(let t, let d, let h): return "Cita «\(t)» el \(day(d))" + (h.map { " a las \(TimeOfDay.text($0))" } ?? "")
        case .measure(let f, let v, let d): return "Medida de \(f.lowercased()): \(MD.formatNumber(v, comma: true)) (\(day(d)))"
        case .shopping(let items): return "Añadir a la compra: \(items.joined(separator: ", "))"
        case .book(let t, let a): return "Añadir a Lecturas: «\(t)»" + (a.isEmpty ? "" : " de \(a)")
        case .finishBook(let t): return "Terminar «\(t)» hoy"
        case .loanPayment(let t): return "Apuntar la cuota de «\(t)»"
        case .expense(let p):
            return (p.amount < 0 ? "Devolución de \(Money.exact(-p.amount))" : "Gasto de \(Money.exact(p.amount))") + (p.category.map { " en \($0)" } ?? "") + (p.note.isEmpty ? "" : " · \(p.note)") + " (\(day(p.date)))"
        }
    }

    private static let measureFields = ["cintura": "Cintura", "cadera": "Cadera", "pecho": "Pecho", "brazo": "Brazo", "muslo": "Muslo", "grasa": "Grasa"]

    /// `categories`, `people` y `learned` son para los gastos («gasto 22 cena con Ana»): sin ellas se usan las partidas de la hoja de Numbers.
    static func parse(_ raw: String, today: Date = DayKey.today(), categories: [String] = Edit.defaultBudgetLines.map(\.0),
                      people: [String] = [], learned: [String: String] = [:]) -> QuickCommand? {
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
            guard let (n, d) = numberAndDate(), n == n.rounded(), (1...5).contains(n) else { return nil }
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
            return .task(p.text, p.date, p.recurrence, p.priority, p.time)
        case "idea": return .idea(arg)
        case "nota", "diario", "apunta", "apunte": return .diary(arg)
        case "cita", "medico":
            let p = NaturalDate.extractDateTime(arg, today: today)
            guard !p.text.isEmpty else { return nil }
            return .appointment(p.text, p.date ?? today, p.time)
        case "gasto", "gaste", "pague", "pago":
            return ExpenseParser.parse(arg, categories: categories, people: people, learned: learned, today: today).map { .expense($0) }
        case "devolucion", "devuelto", "reembolso":
            // La palabra se queda en el texto: es la que hace que el importe cuente como devolución.
            return ExpenseParser.parse(text, categories: categories, people: people, learned: learned, today: today).map { .expense($0) }
        case "compra", "comprar", "lista":
            let items = arg.replacingOccurrences(of: " y ", with: ",").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return items.isEmpty ? nil : .shopping(items)
        case "libro":
            let parts = arg.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let title = parts.first, !title.isEmpty else { return nil }
            return .book(title, parts.dropFirst().joined(separator: " - "))
        case "termine", "terminado", "acabe", "lei": return .finishBook(arg)
        case "cuota": return .loanPayment(arg)
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
    static var file: String { VaultPath.compra }
    /// Secciones de una lista nueva, como los pasillos del súper. Se añaden más al apuntar en otra.
    static let defaultCategories = ["Fruta y verdura", "Carne y pescado", "Lácteos y huevos", "Despensa", "Congelados", "Bebidas", "Limpieza y hogar", "Higiene", "Otros"]

    static var template: String {
        "---\ntipo: compra\ntags:\n  - compra\n---\n\n# Lista de la compra\n\n> Se marca al comprar. «Vaciar comprados» quita lo que ya tienes.\n\n"
            + defaultCategories.map { "## \($0)\n" }.joined(separator: "\n") + "\n---\n"
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
            lines.insertClamped(contentsOf: new, at: last + 1)
        } else {
            // sección nueva antes del pie (no antes del cierre del encabezado YAML, que también es «---»)
            var at = lines.count
            let header = lines.first == "---" ? lines.dropFirst().firstIndex(of: "---") ?? 0 : 0
            if let hr = lines.lastIndex(of: "---"), hr > header { at = hr }
            lines.insertClamped(contentsOf: ["## \(category)"] + new + [""], at: at)
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
