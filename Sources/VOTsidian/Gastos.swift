import Foundation

// Presupuesto mensual: una nota por mes en Finanzas/Gastos (`2026-10.md`) con tres tablas —Ingresos, Partidas y Movimientos—.
// Lo «real» de cada partida es la suma de sus movimientos, así la nota se puede editar a mano en Obsidian sin descuadrar nada.

struct BudgetLine: Identifiable, Equatable {
    enum Kind: String, CaseIterable { case fijo = "Fijo", variable = "Variable", ahorro = "Ahorro" }
    var name: String
    /// Lo que cuenta este mes: el importe si toca pagarla, 0 si es de cada varios meses y este no toca.
    var planned: Double
    var kind: Kind
    var paid: Bool
    var day: Int?
    var line: Int
    /// Lo que se paga cada vez (columna «Previsto»).
    var amount: Double = 0
    /// Cada cuántos meses se paga (columna «Cada»): 1 = todos los meses.
    var every = 1
    /// Primer mes en que tocó (columna «Desde», AAAA-MM); a partir de él se repite cada `every` meses.
    var start: String?
    var id: String { name }

    static let frequencies: [(months: Int, label: String)] = [(1, "Cada mes"), (2, "Cada 2 meses"), (3, "Cada 3 meses"), (4, "Cada 4 meses"), (6, "Cada 6 meses"), (12, "Cada año")]
    static func frequencyLabel(_ n: Int) -> String { frequencies.first { $0.months == n }?.label ?? "Cada \(n) meses" }

    static func monthIndex(_ month: String) -> Int? {
        let p = month.split(separator: "-").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 12 + p[1] - 1 : nil
    }
    static func month(_ index: Int) -> String { String(format: "%04d-%02d", index / 12, index % 12 + 1) }

    func isDue(_ month: String) -> Bool {
        guard every > 1, let s = start.flatMap(BudgetLine.monthIndex), let m = BudgetLine.monthIndex(month) else { return true }
        return ((m - s) % every + every) % every == 0
    }

    /// Próximo mes en que toca, contando `month` si toca en él.
    func nextDue(from month: String) -> String {
        guard let m = BudgetLine.monthIndex(month) else { return month }
        return (0..<max(every, 1)).map { BudgetLine.month(m + $0) }.first(where: isDue) ?? month
    }

    /// Lo que conviene apartar cada mes para tenerlo cuando toque.
    var monthlyReserve: Double { every > 1 ? amount / Double(every) : 0 }
}

struct BudgetIncome: Identifiable, Equatable {
    var name: String
    var planned: Double
    var real: Double?
    var line: Int
    var id: String { name }
}

struct BudgetMove: Identifiable, Equatable {
    var date: Date
    var amount: Double
    var category: String
    var note: String
    var line: Int
    var id: Int { line }
}

struct Budget: Equatable {
    var month: String
    var path: String
    var incomes: [BudgetIncome] = []
    var lines: [BudgetLine] = []
    var moves: [BudgetMove] = []

    static func monthKey(_ d: Date) -> String { String(DayKey.string(d).prefix(7)) }
    static func firstDay(_ month: String) -> Date? { DayKey.date(month + "-01") }
    static func title(_ month: String) -> String {
        guard let d = firstDay(month) else { return month }
        return capitalizedFirst(DayKey.esLong(d, .dateTime.month(.wide).year()))
    }

    /// Lo gastado en una partida: sus movimientos; si no tiene ninguno pero está marcada como pagada, lo previsto.
    func real(_ l: BudgetLine) -> Double {
        let key = MD.fold(l.name)
        let s = moves.filter { MD.fold($0.category) == key }.reduce(0) { $0 + $1.amount }
        return s == 0 && l.paid ? l.planned : s
    }

    /// Movimientos cuya partida no está en la tabla (escrita a mano con otro nombre): cuentan como gasto igualmente.
    var unassigned: Double {
        let names = Set(lines.map { MD.fold($0.name) })
        return moves.filter { !names.contains(MD.fold($0.category)) }.reduce(0) { $0 + $1.amount }
    }

    var income: Double { incomes.reduce(0) { $0 + ($1.real ?? $1.planned) } }
    var planned: Double { lines.reduce(0) { $0 + $1.planned } }
    /// Gasto sin contar el ahorro.
    var spent: Double { lines.filter { $0.kind != .ahorro }.reduce(0) { $0 + real($1) } + unassigned }
    var saved: Double { lines.filter { $0.kind == .ahorro }.reduce(0) { $0 + real($1) } }
    var plannedExpenses: Double { lines.filter { $0.kind != .ahorro }.reduce(0) { $0 + $1.planned } }

    func line(named name: String) -> BudgetLine? { lines.first { MD.fold($0.name) == MD.fold(name) } }
}

/// Cómo va el mes: ritmo de cada partida variable, lo que se puede gastar al día y lo que sobrará.
struct BudgetStatus {
    var day: Int
    var days: Int
    /// `false` en meses pasados o futuros: entonces no hay previsión, solo lo que hubo.
    var isCurrent: Bool
    var variableLeft: Double
    var perDay: Double
    var endLeft: Double
    var projection: [String: Double]

    var fraction: Double { Double(day) / Double(days) }
    var daysLeft: Int { days - day + 1 }

    init(_ b: Budget, today: Date = DayKey.today()) {
        let cal = DayKey.calendar()
        let first = Budget.firstDay(b.month) ?? today
        days = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let current = Budget.monthKey(today) == b.month
        isCurrent = current
        day = current ? cal.component(.day, from: today) : (today < first ? 0 : days)
        let frac = Double(day) / Double(days)
        var proj: [String: Double] = [:]
        for l in b.lines where l.kind == .variable {
            let r = b.real(l)
            // Los primeros días el ritmo engaña (una compra grande el día 1): hasta el 3 se supone lo previsto.
            proj[l.name] = !current ? r : day >= 3 ? max(r, r / frac) : max(r, l.planned)
        }
        projection = proj
        let variables = b.lines.filter { $0.kind == .variable }
        variableLeft = max(0, variables.reduce(0) { $0 + $1.planned - b.real($1) })
        perDay = current ? variableLeft / Double(max(days - day + 1, 1)) : 0
        let others = b.lines.filter { $0.kind != .variable }.reduce(0) { $0 + (current ? max(b.real($1), $1.paid ? 0 : $1.planned) : b.real($1)) }
        endLeft = b.income - others - variables.reduce(0) { $0 + (proj[$1.name] ?? 0) } - b.unassigned
    }

    /// Lo que queda del mes, día a día: real hasta hoy y previsto desde hoy (pagos fijos en su día y variables al ritmo actual).
    func remainingByDay(_ b: Budget) -> (real: [(Int, Double)], forecast: [(Int, Double)]) {
        let cal = DayKey.calendar()
        var spentOn = [Int: Double]()
        for m in b.moves where Budget.monthKey(m.date) == b.month { spentOn[cal.component(.day, from: m.date), default: 0] += m.amount }
        // Partidas pagadas sin movimientos: cuentan en su día, o el 1 si no tienen.
        for l in b.lines where l.paid {
            let key = MD.fold(l.name)
            if !b.moves.contains(where: { MD.fold($0.category) == key }) { spentOn[min(l.day ?? 1, days), default: 0] += l.planned }
        }
        var real: [(Int, Double)] = []
        var left = b.income
        for d in 1...max(day, 1) { left -= spentOn[d] ?? 0; real.append((d, left)) }
        guard isCurrent, day < days else { return (real, []) }
        var pendingOn = [Int: Double]()
        for l in b.lines where l.kind != .variable && !l.paid && b.real(l) == 0 { pendingOn[min(max(l.day ?? days, day + 1), days), default: 0] += l.planned }
        let variableSpent = b.lines.filter { $0.kind == .variable }.reduce(0) { $0 + b.real($1) }
        let rate = day > 0 ? variableSpent / Double(day) : 0
        var forecast: [(Int, Double)] = [(day, left)]
        for d in (day + 1)...days { left -= (pendingOn[d] ?? 0) + rate; forecast.append((d, left)) }
        return (real, forecast)
    }
}

struct BudgetInsight: Identifiable, Equatable {
    enum Level { case info, warn, bad, good }
    var id: String
    var level: Level
    var text: String
    /// Partida cuyos movimientos se pueden ver desde el aviso.
    var category: String? = nil
    /// Nota que abre el aviso (un evento con aportación pendiente).
    var notePath: String? = nil
}

extension Budget {
    /// Avisos del mes: facturas que suben respecto a la media, partidas que se pasan varios meses seguidos,
    /// aportaciones de eventos sin pagar y lo que sobrará si se sigue al ritmo actual.
    static func insights(_ b: Budget, previous: [Budget], status s: BudgetStatus,
                         events: [(name: String, amount: Double, path: String)] = []) -> [BudgetInsight] {
        var out: [BudgetInsight] = []
        for l in b.lines {
            let past = previous.compactMap { p in p.line(named: l.name).map { p.real($0) } }.filter { $0 > 0 }
            guard !past.isEmpty else { continue }
            let avg = past.reduce(0, +) / Double(past.count)
            let r = b.real(l)
            if l.kind == .fijo, r > 0, r >= avg * 1.1, r - avg >= 5 {
                out.append(BudgetInsight(id: "sube-\(l.name)", level: .warn,
                    text: "\(l.name): \(Money.format(r)), un \(Int(((r - avg) / avg * 100).rounded())) % más que tu media de \(past.count == 1 ? "el mes anterior" : "los últimos \(past.count) meses") (\(Money.format(avg))). Si cambió la tarifa, sube lo previsto.",
                    category: l.name))
            }
            if l.kind == .variable, l.planned > 0 {
                let overBefore = previous.prefix(2).allSatisfy { p in p.line(named: l.name).map { p.real($0) > $0.planned } ?? false }
                let overNow = (s.projection[l.name] ?? r) > l.planned
                if previous.count >= 2, overBefore, overNow {
                    out.append(BudgetInsight(id: "pasa-\(l.name)", level: .bad,
                        text: "\(l.name) se pasa de lo previsto por tercer mes (media \(Money.format(avg)) frente a \(Money.format(l.planned))). O lo previsto es poco, o es la partida a recortar.",
                        category: l.name))
                }
            }
        }
        if s.isCurrent, let m = BudgetLine.monthIndex(b.month) {
            let next = BudgetLine.month(m + 1)
            let due = b.lines.filter { $0.every > 1 && $0.isDue(next) && $0.amount > 0 }
            if !due.isEmpty {
                let total = due.reduce(0) { $0 + $1.amount }
                out.append(BudgetInsight(id: "proximo-mes", level: .info,
                    text: "En \(Budget.title(next).lowercased()) toca \(due.map { "\($0.name) (\(Money.format($0.amount)))" }.joined(separator: ", ")): \(Money.format(total)) más que un mes normal."))
            }
        }
        for e in events where e.amount > 0 {
            out.append(BudgetInsight(id: "evento-\(e.path)", level: .info, text: "\(e.name): aportación de \(Money.format(e.amount)) sin pagar.", notePath: e.path))
        }
        if s.isCurrent, s.day >= 3 {
            if s.endLeft > 50 {
                out.append(BudgetInsight(id: "sobra", level: .good, text: "A este ritmo sobrarán ~\(Money.format(s.endLeft)) el \(s.days). Al cerrar el mes puedes pasarlos al fondo de emergencia."))
            } else if s.endLeft < 0 {
                out.append(BudgetInsight(id: "falta", level: .bad, text: "A este ritmo faltarán ~\(Money.format(-s.endLeft)) a fin de mes. Mira qué partida variable se puede frenar."))
            }
        }
        return out
    }
}

// MARK: - Leer y escribir la nota del mes

extension Parse {
    static func budget(_ text: String, month: String, path: String) -> Budget {
        var b = Budget(month: month, path: path)
        let lines = MD.lines(text)
        func rows(_ section: String) -> (header: [String], rows: [(index: Int, cells: [String])])? {
            guard let r = MD.section(lines, containing: section) else { return nil }
            let t = MD.tableRows(lines).filter { r.contains($0.index) }
            guard let h = t.first else { return nil }
            let data = t.dropFirst().filter { !$0.cells.allSatisfy { $0.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil } }
            return (h.cells, Array(data))
        }
        func col(_ header: [String], _ names: String...) -> Int? { header.firstIndex { h in names.contains(MD.fold(h)) } }
        func cell(_ c: [String], _ i: Int?) -> String { i.flatMap { $0 < c.count ? c[$0] : nil } ?? "" }
        func amount(_ s: String) -> Double? { s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Money.parse(s) }

        if let t = rows("Ingresos") {
            let n = col(t.header, "concepto", "ingreso") ?? 0, p = col(t.header, "previsto"), r = col(t.header, "real")
            for row in t.rows where !cell(row.cells, n).isEmpty {
                b.incomes.append(BudgetIncome(name: cell(row.cells, n), planned: amount(cell(row.cells, p)) ?? 0, real: amount(cell(row.cells, r)), line: row.index))
            }
        }
        if let t = rows("Partidas") {
            let n = col(t.header, "partida") ?? 0, p = col(t.header, "previsto"), k = col(t.header, "tipo"), pd = col(t.header, "pagado"), d = col(t.header, "dia")
            let ev = col(t.header, "cada"), st = col(t.header, "desde")
            for row in t.rows where !cell(row.cells, n).isEmpty {
                let kind = BudgetLine.Kind.allCases.first { MD.fold($0.rawValue) == MD.fold(cell(row.cells, k)) } ?? .variable
                let paid = cell(row.cells, pd)
                let full = amount(cell(row.cells, p)) ?? 0
                // «3», «3 meses», «trimestral», «anual»…
                let everyText = MD.fold(cell(row.cells, ev))
                let every = everyText.contains("anual") || everyText.contains("ano") ? 12 : everyText.contains("semestr") ? 6 : everyText.contains("trimestr") ? 3
                    : everyText.contains("bimestr") ? 2 : everyText.firstMatch(of: /(\d{1,2})/).flatMap { Int($0.1) }.map { max($0, 1) } ?? 1
                let start = cell(row.cells, st).range(of: #"^\d{4}-\d{2}"#, options: .regularExpression).map { String(cell(row.cells, st)[$0]) }
                var l = BudgetLine(name: cell(row.cells, n), planned: full, kind: kind,
                                   paid: paid.contains("✅") || ["x", "si", "pagado"].contains(MD.fold(paid)),
                                   day: Int(cell(row.cells, d)).flatMap { (1...31).contains($0) ? $0 : nil }, line: row.index,
                                   amount: full, every: every, start: start ?? (every > 1 ? month : nil))
                if !l.isDue(month) { l.planned = 0; l.paid = false }
                b.lines.append(l)
            }
        }
        if let t = rows("Movimientos") {
            let f = col(t.header, "fecha") ?? 0, a = col(t.header, "importe"), c = col(t.header, "partida"), no = col(t.header, "nota")
            for row in t.rows {
                guard let date = DayKey.date(cell(row.cells, f)) ?? DayKey.dmyDate(cell(row.cells, f)), let v = amount(cell(row.cells, a)) else { continue }
                b.moves.append(BudgetMove(date: date, amount: v, category: cell(row.cells, c), note: cell(row.cells, no), line: row.index))
            }
        }
        return b
    }
}

extension Edit {
    /// Número para la nota: sin decimales si es entero, con coma y dos decimales si no («63,40»).
    static func budgetNumber(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// Las partidas de tu hoja de Numbers, para el primer mes.
    static let defaultBudgetLines: [(String, BudgetLine.Kind)] = [
        ("Vivienda (alquiler, hipoteca, impuestos, seguro)", .fijo), ("Alimentación", .variable), ("Transporte", .variable),
        ("Suministros agua y luz", .fijo), ("Restaurantes, viajes, entretenimiento", .variable), ("Préstamo padre", .fijo),
        ("Préstamo personal", .fijo), ("Ordenador", .fijo), ("Seguro vida", .fijo), ("Gym + O2", .fijo), ("Gastos comunidad", .fijo),
        ("Imprevistos / otros", .variable), ("Ahorro / fondo de emergencia", .ahorro), ("Suscripciones (Music + iCloud)", .fijo),
    ]

    /// Nota de un mes nuevo. Copia ingresos, partidas, lo previsto y los días del mes anterior; «Real» y «Pagado» empiezan vacíos.
    static func budgetNote(month: String, from previous: Budget?) -> String {
        let incomes = previous?.incomes.map { ($0.name, $0.planned) } ?? [("Nómina", 0), ("Ingresos adicionales", 0)]
        let lines = previous?.lines.map { ($0.name, $0.amount, $0.kind, $0.day, $0.every, $0.start) }
            ?? defaultBudgetLines.map { ($0.0, 0, $0.1, nil, 1, nil) }
        var out = ["---", "tipo: presupuesto", "mes: \(month)", "---", "", "# Gastos · \(Budget.title(month))", "",
                   "## Ingresos", "| Concepto | Previsto | Real |", "| :--- | ---: | ---: |"]
        out += incomes.map { rowString([$0.0, budgetNumber($0.1), ""]) }
        out += ["", "## Partidas", "| Partida | Previsto | Tipo | Pagado | Día | Cada | Desde |", "| :--- | ---: | :--- | :---: | ---: | :---: | :--- |"]
        out += lines.map { rowString([$0.0, budgetNumber($0.1), $0.2.rawValue, "", $0.3.map(String.init) ?? "", $0.4 > 1 ? "\($0.4)" : "", $0.4 > 1 ? $0.5 ?? "" : ""]) }
        out += ["", "## Movimientos", "| Fecha | Importe | Partida | Nota |", "| :--- | ---: | :--- | :--- |", "", "---", "[[Finanzas]]", ""]
        return out.joined(separator: "\n")
    }

    /// Deja la tabla de una sección lista para editar celdas: en Partidas añade «Cada» y «Desde» si es de antes de las
    /// frecuencias, y completa las filas con menos celdas que la cabecera (escritas a mano), que si no no se podrían cambiar.
    static func normalizeBudgetTable(_ text: String, section: String) -> String {
        var lines = MD.lines(text)
        guard let r = MD.section(lines, containing: section) else { return text }
        let rows = MD.tableRows(lines).filter { r.contains($0.index) }
        guard var header = rows.first?.cells else { return text }
        let addFrequency = MD.fold(section) == "partidas" && !header.contains { MD.fold($0) == "cada" }
        if addFrequency { header += ["Cada", "Desde"] }
        for (i, row) in rows.enumerated() {
            let isSeparator = row.cells.allSatisfy { $0.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil }
            var cells = i == 0 ? header : row.cells
            if i > 0, addFrequency, isSeparator, cells.count < header.count { cells += [":---:", ":---"] }
            while cells.count < header.count { cells.append(isSeparator && i > 0 ? "---" : "") }
            if cells != row.cells { lines[row.index] = rowString(cells) }
        }
        return lines.joined(separator: "\n")
    }

    /// Añade una partida al final de la tabla de Partidas.
    static func addBudgetLine(_ text: String, name: String, amount: Double, kind: BudgetLine.Kind, every: Int, start: String?) -> String? {
        let t = normalizeBudgetTable(text, section: "Partidas")
        var lines = MD.lines(t)
        guard let r = MD.section(lines, containing: "Partidas"), let last = MD.tableRows(lines).last(where: { r.contains($0.index) }) else { return nil }
        lines.insert(rowString([name, budgetNumber(amount), kind.rawValue, "", "", every > 1 ? String(every) : "", every > 1 ? start ?? "" : ""]), at: last.index + 1)
        return lines.joined(separator: "\n")
    }

    /// Cambia el nombre de una partida y el de sus movimientos, para que sigan contando en ella.
    static func renameBudgetLine(_ text: String, line: Int, from old: String, to new: String) -> String? {
        var lines = MD.lines(text)
        guard line < lines.count, MD.cells(lines[line]).first == old, let r = MD.section(lines, containing: "Movimientos") else { return nil }
        var cells = MD.cells(lines[line]); cells[0] = new
        lines[line] = rowString(cells)
        let rows = MD.tableRows(lines).filter { r.contains($0.index) }
        guard let col = rows.first?.cells.firstIndex(where: { MD.fold($0) == "partida" }) else { return lines.joined(separator: "\n") }
        for row in rows.dropFirst() where col < row.cells.count && MD.fold(row.cells[col]) == MD.fold(old) {
            var c = row.cells; c[col] = new
            lines[row.index] = rowString(c)
        }
        return lines.joined(separator: "\n")
    }

    /// Añade un movimiento al final de la tabla de Movimientos.
    static func addBudgetMove(_ text: String, date: Date, amount: Double, category: String, note: String) -> String? {
        var lines = MD.lines(text)
        guard let r = MD.section(lines, containing: "Movimientos") else { return nil }
        guard let last = MD.tableRows(lines).last(where: { r.contains($0.index) }) else { return nil }
        lines.insert(rowString([DayKey.string(date), budgetNumber(amount), category, note]), at: last.index + 1)
        return lines.joined(separator: "\n")
    }
}

// MARK: - Entender «22 € cena con Ana»

enum ExpenseParser {
    struct Result: Equatable { var amount: Double; var category: String?; var note: String; var person: String?; var date: Date }

    /// Palabras que llevan a una partida aunque su nombre no aparezca: se buscan dentro del nombre de las partidas.
    private static let hints: [(words: [String], partida: [String])] = [
        (["cena", "comida fuera", "restaurante", "bar", "cafe", "copas", "cine", "concierto", "viaje", "hotel", "vuelo", "entrada"], ["restaurante", "ocio", "entreten"]),
        (["gasolina", "metro", "taxi", "uber", "cabify", "bus", "autobus", "parking", "tren", "peaje", "renfe"], ["transporte"]),
        (["mercadona", "super", "supermercado", "compra", "carrefour", "lidl", "dia", "fruta", "aldi", "alcampo"], ["alimenta", "comida"]),
        (["luz", "agua", "gas", "factura", "endesa", "iberdrola"], ["suministro", "luz"]),
        (["gym", "gimnasio", "o2"], ["gym"]),
        (["spotify", "netflix", "icloud", "music", "hbo", "disney", "suscripcion"], ["suscrip"]),
        (["comunidad"], ["comunidad"]),
        (["ahorro", "fondo"], ["ahorro"]),
    ]

    static func parse(_ input: String, categories: [String], people: [String] = [], today: Date = DayKey.today()) -> Result? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard let m = text.firstMatch(of: /(\d{1,6}(?:[.,]\d{1,2})?)\s*(?:€|eur(?:os)?\b)?/), let amount = Double(String(m.1).replacingOccurrences(of: ",", with: ".")), amount > 0 else { return nil }
        var rest = text
        rest.removeSubrange(m.range)
        let dated = NaturalDate.extract(rest, today: today)
        rest = dated.text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        rest = rest.replacingOccurrences(of: #"^(?i)(en|de|del|por)\s+"#, with: "", options: .regularExpression)
        let folded = " " + MD.fold(rest).replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression) + " "

        // Primero, una palabra del propio nombre de la partida («gym», «transporte»); después, las pistas.
        var category = categories.first { c in
            MD.fold(c).split { !$0.isLetter }.map(String.init).filter { $0.count >= 4 }.contains { folded.contains(" \($0) ") }
        }
        if category == nil {
            for h in hints where h.words.contains(where: { folded.contains(" \($0) ") }) {
                if let c = categories.first(where: { c in h.partida.contains { MD.fold(c).contains($0) } }) { category = c; break }
            }
        }
        if category == nil { category = categories.first { MD.fold($0).contains("imprevist") } }

        var person: String?
        for p in people where p.count >= 3 {
            let key = MD.fold(p)
            if folded.contains(" \(key) "), let r = rest.range(of: p, options: [.caseInsensitive, .diacriticInsensitive]) {
                person = p
                rest.replaceSubrange(r, with: "[[\(p)]]")
                break
            }
        }
        return Result(amount: amount, category: category, note: rest, person: person, date: dated.date ?? today)
    }
}

// MARK: - Store

extension Store {
    static var gastosFolder: String { VaultPath.path("gastos") }
    func budgetPath(_ month: String) -> String { "\(Store.gastosFolder)/\(month).md" }

    /// Meses con nota de presupuesto, del más viejo al más nuevo.
    var budgetMonths: [String] {
        let prefix = Store.gastosFolder + "/"
        return notes.compactMap { n in
            guard n.path.hasPrefix(prefix), n.name.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
            return n.name
        }.sorted()
    }

    func budget(_ month: String) -> Budget? {
        let p = budgetPath(month)
        guard let t = noteTexts[p] else { return nil }
        return Parse.budget(t, month: month, path: p)
    }

    /// Los `limit` meses con nota anteriores a `month`, del más reciente al más viejo.
    func budgets(before month: String, limit: Int = 3) -> [Budget] {
        budgetMonths.filter { $0 < month }.reversed().prefix(limit).compactMap { budget($0) }
    }

    /// Crea la nota del mes copiando la estructura del último mes que haya.
    @discardableResult
    func createBudget(_ month: String) -> Bool {
        guard budget(month) == nil else { return true }
        let previous = budgetMonths.last { $0 < month }.flatMap { budget($0) } ?? budgetMonths.last.flatMap { budget($0) }
        return writeNote(budgetPath(month), text: Edit.budgetNote(month: month, from: previous))
    }

    func addExpense(_ amount: Double, category: String, note: String, date: Date) {
        let month = Budget.monthKey(date)
        guard createBudget(month) else { return }
        edit(budgetPath(month)) { Edit.addBudgetMove($0, date: date, amount: amount, category: category, note: note) }
    }

    func setBudgetCell(_ b: Budget, section: String, line: Int, name: String, column: String, value: String) {
        edit(b.path) { Edit.setSectionCell(Edit.normalizeBudgetTable($0, section: section), section: section, line: line, expectFirst: name, column: column, value: value) }
    }

    /// Cambia cada cuántos meses se paga una partida y desde qué mes. Afecta a este mes y a los que se creen después.
    func setBudgetFrequency(_ b: Budget, _ l: BudgetLine, every: Int, start: String?) {
        edit(b.path) { text in
            var t = Edit.normalizeBudgetTable(text, section: "Partidas")
            for (column, value) in [("Cada", every > 1 ? String(every) : ""), ("Desde", every > 1 ? start ?? b.month : "")] {
                guard let next = Edit.setSectionCell(t, section: "Partidas", line: l.line, expectFirst: l.name, column: column, value: value) else { return nil }
                t = next
            }
            return t
        }
    }

    func addBudgetLine(_ b: Budget, name: String, amount: Double, kind: BudgetLine.Kind, every: Int, start: String?) {
        let clean = name.replacingOccurrences(of: "|", with: "/").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        guard b.line(named: clean) == nil else { message = "Ya hay una partida llamada «\(clean)»."; return }
        edit(b.path) { Edit.addBudgetLine($0, name: clean, amount: amount, kind: kind, every: every, start: start) }
    }

    func renameBudgetLine(_ b: Budget, _ l: BudgetLine, to name: String) {
        let clean = name.replacingOccurrences(of: "|", with: "/").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean != l.name else { return }
        guard b.line(named: clean) == nil || MD.fold(clean) == MD.fold(l.name) else { message = "Ya hay una partida llamada «\(clean)»."; return }
        edit(b.path) { Edit.renameBudgetLine($0, line: l.line, from: l.name, to: clean) }
    }

    /// Quita la partida de este mes. Sus movimientos se quedan en la nota y siguen contando como gasto.
    func removeBudgetLine(_ b: Budget, _ l: BudgetLine) {
        edit(b.path) { Edit.deleteRow($0, line: l.line, expectFirst: l.name) }
    }

    func deleteExpense(_ b: Budget, _ m: BudgetMove) {
        // La fila se borra solo si sigue siendo ese gasto (misma fecha e importe): si la nota cambió, no se toca otra.
        edit(b.path) { text in
            guard let now = Parse.budget(text, month: b.month, path: b.path).moves.first(where: { $0.line == m.line }),
                  now.date == m.date, now.amount == m.amount else { return nil }
            return Edit.deleteRow(text, line: m.line, expectFirst: MD.cells(MD.lines(text)[m.line]).first ?? "")
        }
    }

    /// Eventos de Finanzas con aportación sin pagar.
    var pendingContributions: [(name: String, amount: Double, path: String)] {
        noteMeta.compactMap { path, m in
            guard m["tipo"] == "evento", m["estado"] != "pagado", m["estado"] != "cancelado" else { return nil }
            let v = Money.parse(m["aportacion_eur"] ?? "")
            return v > 0 ? (((path as NSString).lastPathComponent as NSString).deletingPathExtension, v, path) : nil
        }.sorted { $0.name < $1.name }
    }
}
