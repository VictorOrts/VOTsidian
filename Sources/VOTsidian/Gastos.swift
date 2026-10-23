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
    /// Por línea, no por nombre: dos partidas llamadas igual en la nota no se confunden en la tabla.
    var id: Int { line }

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

    /// Gasto del día a día (variable y de cada mes): el que tiene ritmo y entra en «puedes gastar hoy».
    /// Un cargo de cada varios meses, aunque su importe varíe, se trata como un pago fijo del mes en que toca.
    var isDiscretionary: Bool { kind == .variable && every == 1 }

    /// Lo que conviene apartar cada mes para tenerlo cuando toque.
    var monthlyReserve: Double { every > 1 ? amount / Double(every) : 0 }
}

struct BudgetIncome: Identifiable, Equatable {
    var name: String
    var planned: Double
    var real: Double?
    var line: Int
    var id: Int { line }
}

struct BudgetMove: Identifiable, Equatable {
    var date: Date
    var amount: Double
    var category: String { didSet { key = MD.fold(category) } }
    var note: String
    var line: Int
    /// `category` plegada (sin tildes ni mayúsculas): se compara con cada partida muchas veces por pintado.
    private(set) var key: String
    var id: Int { line }

    init(date: Date, amount: Double, category: String, note: String, line: Int) {
        self.date = date; self.amount = amount; self.category = category; self.note = note; self.line = line
        key = MD.fold(category)
    }
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
    /// Un gasto y su devolución que suman 0 son 0, no lo previsto: lo que cuenta es que haya movimientos.
    func real(_ l: BudgetLine) -> Double {
        let key = MD.fold(l.name)
        let mine = moves.filter { $0.key == key }
        return mine.isEmpty && l.paid ? l.planned : mine.reduce(0) { $0 + $1.amount }
    }

    /// Movimientos cuya partida no está en la tabla (escrita a mano con otro nombre): cuentan como gasto igualmente.
    var unassigned: Double {
        let names = Set(lines.map { MD.fold($0.name) })
        return moves.filter { !names.contains($0.key) }.reduce(0) { $0 + $1.amount }
    }

    var income: Double { incomes.reduce(0) { $0 + ($1.real ?? $1.planned) } }
    var planned: Double { lines.reduce(0) { $0 + $1.planned } }
    /// Gasto sin contar el ahorro.
    var spent: Double { lines.filter { $0.kind != .ahorro }.reduce(0) { $0 + real($1) } + unassigned }
    var saved: Double { lines.filter { $0.kind == .ahorro }.reduce(0) { $0 + real($1) } }
    var plannedExpenses: Double { lines.filter { $0.kind != .ahorro }.reduce(0) { $0 + $1.planned } }
    /// Gasto previsto de un mes típico: los cargos de cada varios meses cuentan su parte (el seguro anual, 1/12).
    /// No cambia según toque o no un cargo este mes, así que sirve de base para el fondo de emergencia.
    var typicalMonthExpenses: Double { lines.filter { $0.kind != .ahorro }.reduce(0) { $0 + $1.amount / Double(max($1.every, 1)) } }

    /// Fijos que tocaban este mes, con algo previsto, sin marcar ni ningún movimiento.
    var unpaidFixed: [BudgetLine] { lines.filter { !$0.isDiscretionary && $0.kind != .ahorro && $0.planned > 0 && !$0.paid && real($0) == 0 } }

    /// Movimientos con una partida que no está en la tabla, agrupados por ese nombre: así se ve qué partida falta.
    var unassignedByCategory: [(name: String, total: Double)] {
        let names = Set(lines.map { MD.fold($0.name) })
        var out: [(name: String, total: Double)] = []
        for m in moves where !names.contains(m.key) {
            if let i = out.firstIndex(where: { MD.fold($0.name) == m.key }) { out[i].total += m.amount } else { out.append((m.category, m.amount)) }
        }
        return out
    }

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
    /// Gastado hoy en partidas variables.
    var spentToday: Double = 0
    /// Lo que tocaba gastar hoy al empezar el día: lo que quedaba para variables repartido entre los días que faltan.
    var todayAllowance: Double = 0
    /// Lo que queda de lo de hoy. Gastar hoy baja este número, no el de mañana: con `perDay` solo, un gasto
    /// de 25 € un día de 10 € apenas movía «Puedes gastar hoy».
    var leftToday: Double { max(0, todayAllowance - spentToday) }

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
        for l in b.lines where l.isDiscretionary {
            let r = b.real(l)
            // Los primeros días el ritmo engaña (una compra grande el día 1): hasta el 3 se supone lo previsto.
            // Sin nada apuntado tampoco hay ritmo (lo normal es que aún no lo hayas apuntado): se supone lo previsto.
            proj[l.name] = !current ? r : day >= 3 && r > 0 ? max(r, r / frac) : max(r, l.planned)
        }
        projection = proj
        let variables = b.lines.filter(\.isDiscretionary)
        let others = b.lines.filter { !$0.isDiscretionary }.reduce(0) { $0 + (current ? max(b.real($1), $1.paid ? 0 : $1.planned) : b.real($1)) }
        // Lo que queda en variables según lo previsto, pero nunca más que el dinero que de verdad queda tras los fijos:
        // si los ingresos no cubren lo previsto, «puedes gastar hoy» no puede prometer lo que no hay.
        let cash = b.income - others - variables.reduce(0) { $0 + b.real($1) } - b.unassigned
        let plannedLeft = variables.reduce(0) { $0 + $1.planned - b.real($1) }
        variableLeft = max(0, min(plannedLeft, cash))
        perDay = current ? variableLeft / Double(max(days - day + 1, 1)) : 0
        endLeft = b.income - others - variables.reduce(0) { $0 + (proj[$1.name] ?? 0) } - b.unassigned
        if current {
            let keys = Set(variables.map { MD.fold($0.name) })
            let todayKey = DayKey.string(today)
            spentToday = b.moves.filter { DayKey.string($0.date) == todayKey && keys.contains($0.key) }.reduce(0) { $0 + $1.amount }
            todayAllowance = max(0, min(plannedLeft + spentToday, cash + spentToday)) / Double(max(days - day + 1, 1))
        }
    }

    /// Lo que queda del mes, día a día: real hasta hoy y previsto desde hoy (pagos fijos en su día y variables al ritmo actual).
    func remainingByDay(_ b: Budget) -> (real: [(Int, Double)], forecast: [(Int, Double)]) {
        let cal = DayKey.calendar()
        var spentOn = [Int: Double]()
        // Un movimiento con fecha de otro mes (escrito a mano) cuenta igual que en el total: el primer o el último día.
        for m in b.moves {
            let k = Budget.monthKey(m.date)
            let d = k == b.month ? cal.component(.day, from: m.date) : k < b.month ? 1 : days
            spentOn[d, default: 0] += m.amount
        }
        // Partidas pagadas sin movimientos: cuentan en su día, o el 1 si no tienen. Si está marcada pero su día aún no ha
        // llegado (se pagó antes), cuenta hoy: ese dinero ya no está y «Hoy quedan» no debe contarlo.
        for l in b.lines where l.paid {
            let key = MD.fold(l.name)
            if !b.moves.contains(where: { $0.key == key }) { spentOn[min(l.day ?? 1, isCurrent ? max(day, 1) : days), default: 0] += l.planned }
        }
        var real: [(Int, Double)] = []
        var left = b.income
        for d in 1...max(day, 1) { left -= spentOn[d] ?? 0; real.append((d, left)) }
        guard isCurrent, day < days else { return (real, []) }
        // Lo que falta de cada fijo sin pagar (entero o lo que quede si ya se pagó una parte), en su día.
        var pendingOn = [Int: Double]()
        for l in b.lines where !l.isDiscretionary && !l.paid {
            let left = l.planned - b.real(l)
            if left > 0 { pendingOn[min(max(l.day ?? days, day + 1), days), default: 0] += left }
        }
        // Los variables bajan hasta su previsión (la misma que usa «Sobrará»), repartida entre los días que quedan.
        let variables = b.lines.filter(\.isDiscretionary)
        let rate = variables.reduce(0) { $0 + (projection[$1.name] ?? b.real($1)) - b.real($1) } / Double(days - day)
        var forecast: [(Int, Double)] = [(day, left)]
        // Los gastos apuntados por adelantado («mañana comunidad 60») bajan en su día.
        for d in (day + 1)...days { left -= (spentOn[d] ?? 0) + (pendingOn[d] ?? 0) + rate; forecast.append((d, left)) }
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
    /// Aportación de un evento que se puede dar por pagada y apuntar como gasto desde el aviso.
    var pay: Double? = nil
    /// Sobrante de un mes cerrado que se puede pasar al fondo de emergencia.
    var transfer: Double? = nil
    /// Mes del que es el sobrante (puede ser el anterior al que se está viendo).
    var month: String? = nil
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
            if !l.isDiscretionary, l.kind != .ahorro, r > l.planned, r >= avg * 1.1, r - avg >= 5 {
                out.append(BudgetInsight(id: "sube-\(l.name)", level: .warn,
                    text: "\(l.name): \(Money.format(r)), un \(Int(((r - avg) / avg * 100).rounded())) % más que tu media de \(past.count == 1 ? "el mes anterior" : "los últimos \(past.count) meses") (\(Money.format(avg))). Si cambió la tarifa, sube lo previsto.",
                    category: l.name))
            }
            if l.isDiscretionary, l.planned > 0 {
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
            out.append(BudgetInsight(id: "evento-\(e.path)", level: .info, text: "\(e.name): aportación de \(Money.format(e.amount)) sin pagar.", notePath: e.path, pay: e.amount))
        }
        if !s.isCurrent, s.day == s.days { out += closing(b) }
        // Mes en curso o por venir con muchas partidas sin importe: sin lo previsto, ni el ritmo ni «Sobrará» dicen nada.
        let empty = b.lines.filter { $0.amount == 0 && $0.kind != .ahorro && b.real($0) == 0 }
        if s.isCurrent || s.day == 0, empty.count >= 3 {
            out.append(BudgetInsight(id: "sin-previsto", level: .info,
                text: "\(empty.count) partidas tienen 0 € previstos (\(empty.prefix(3).map(\.name).joined(separator: ", "))\(empty.count > 3 ? "…" : "")). Pon lo que sueles gastar en ellas o quítalas si no las usas."))
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

    /// Avisos de un mes ya cerrado: pagos sin marcar y el sobrante para el fondo. Salen al mirar ese mes y, los primeros
    /// días, también en el mes en curso, que es donde se está al empezar el mes.
    static func closing(_ b: Budget) -> [BudgetInsight] {
        var out: [BudgetInsight] = []
        let name = Budget.title(b.month).lowercased()
        // Un fijo sin marcar ni apuntar puede ser un pago olvidado. Se avisa y no entra en el sobrante,
        // para no pasar al fondo dinero que en realidad se fue en esa factura.
        let unpaid = b.unpaidFixed
        if !unpaid.isEmpty {
            out.append(BudgetInsight(id: "sin-marcar-\(b.month)", level: .warn,
                text: "En \(name) quedaron sin marcar como pagados: \(unpaid.map { "\($0.name) (\(Money.format($0.planned)))" }.joined(separator: ", ")). Si los pagaste, márcalos en la tabla de partidas de ese mes."))
        }
        if b.lines.contains(where: { $0.kind == .ahorro }) {
            let left = b.income - b.spent - b.saved - unpaid.reduce(0) { $0 + $1.planned }
            if left >= 5 {
                out.append(BudgetInsight(id: "cierre-\(b.month)", level: .good, text: "En \(name) sobraron \(Money.exact(left))\(unpaid.isEmpty ? "" : " (sin contar los pagos sin marcar)"). Pásalos al fondo de emergencia para que no se diluyan en el mes siguiente.", transfer: left, month: b.month))
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
                let times = everyText.firstMatch(of: /(\d{1,2})/).flatMap { Int($0.1) }.map { max($0, 1) }
                let every = everyText.contains("anual") ? 12 : everyText.contains("ano") ? (times ?? 1) * 12 : everyText.contains("semestr") ? 6
                    : everyText.contains("trimestr") ? 3 : everyText.contains("bimestr") ? 2 : times ?? 1
                let start = cell(row.cells, st).range(of: #"^\d{4}-\d{2}"#, options: .regularExpression).map { String(cell(row.cells, st)[$0]) }
                var l = BudgetLine(name: cell(row.cells, n), planned: full, kind: kind,
                                   paid: ["✅", "✔", "☑", "✓"].contains { paid.contains($0) } || ["x", "[x]", "si", "pagado", "pagada"].contains(MD.fold(paid)),
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

    /// Partidas del primer mes, para empezar: luego se renombran, se quitan o se añaden. Los meses siguientes copian las del anterior.
    static let defaultBudgetLines: [(String, BudgetLine.Kind)] = [
        ("Vivienda (alquiler o hipoteca)", .fijo), ("Suministros (luz, agua, gas)", .fijo), ("Internet y móvil", .fijo),
        ("Alimentación", .variable), ("Transporte", .variable), ("Restaurantes y ocio", .variable), ("Salud y deporte", .variable),
        ("Ropa y cuidado personal", .variable), ("Seguros", .fijo), ("Suscripciones", .fijo), ("Imprevistos / otros", .variable),
        ("Ahorro / fondo de emergencia", .ahorro),
    ]

    /// Nota de un mes nuevo. Copia ingresos, partidas, lo previsto y los días del mes anterior; «Real» y «Pagado» empiezan vacíos.
    static func budgetNote(month: String, from previous: Budget?, defaults: [(String, BudgetLine.Kind)] = defaultBudgetLines) -> String {
        let incomes = previous?.incomes.map { ($0.name, $0.planned) } ?? [("Nómina", 0), ("Ingresos adicionales", 0)]
        let lines = previous?.lines.map { ($0.name, $0.amount, $0.kind, $0.day, $0.every, $0.start) }
            ?? defaults.map { ($0.0, 0, $0.1, nil, 1, nil) }
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

    /// Añade un concepto al final de la tabla de Ingresos, sin importes.
    static func addBudgetIncome(_ text: String, name: String) -> String? {
        let t = normalizeBudgetTable(text, section: "Ingresos")
        var lines = MD.lines(t)
        guard let r = MD.section(lines, containing: "Ingresos") else { return nil }
        let rows = MD.tableRows(lines).filter { r.contains($0.index) }
        guard let last = rows.last, let width = rows.first?.cells.count else { return nil }
        lines.insert(rowString([name] + Array(repeating: "", count: max(width - 1, 0))), at: last.index + 1)
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
        guard line < lines.count, MD.cells(lines[line]).first == old else { return nil }
        var cells = MD.cells(lines[line]); cells[0] = new
        lines[line] = rowString(cells)
        guard let r = MD.section(lines, containing: "Movimientos") else { return lines.joined(separator: "\n") }
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

    /// Cambia fecha, importe y nota de un movimiento, solo si la fila sigue siendo ese movimiento (misma fecha e importe).
    static func updateBudgetMove(_ text: String, month: String, move m: BudgetMove, date: Date, amount: Double, note: String) -> String? {
        guard let now = Parse.budget(text, month: month, path: "").moves.first(where: { $0.line == m.line }), now.date == m.date, now.amount == m.amount else { return nil }
        var t = normalizeBudgetTable(text, section: "Movimientos")
        // Solo lo que cambia: una tabla escrita a mano sin columna «Nota» se puede corregir igual si la nota no se toca.
        let changes = [("Fecha", DayKey.string(date), date != m.date), ("Importe", budgetNumber(amount), amount != m.amount), ("Nota", note, note != m.note)]
        for (column, value, _) in changes.filter(\.2) {
            guard let first = MD.cells(MD.lines(t)[m.line]).first,
                  let next = setSectionCell(t, section: "Movimientos", line: m.line, expectFirst: first, column: column, value: value) else { return nil }
            t = next
        }
        return t
    }
}

// MARK: - Entender «22 € cena con Ana»

enum ExpenseParser {
    struct Result: Equatable { var amount: Double; var category: String?; var note: String; var person: String?; var date: Date }

    /// Palabras que llevan a una partida aunque su nombre no aparezca: se buscan dentro del nombre de las partidas.
    private static let hints: [(words: [String], partida: [String])] = [
        (["cena", "comida fuera", "restaurante", "bar", "cafe", "copas", "cine", "concierto", "viaje", "hotel", "vuelo", "entrada"], ["restaurante", "ocio", "entreten"]),
        (["gasolina", "metro", "taxi", "uber", "cabify", "bus", "autobus", "parking", "tren", "peaje", "renfe"], ["transporte"]),
        (["mercadona", "super", "supermercado", "compra", "carrefour", "lidl", "fruta", "aldi", "alcampo", "eroski", "consum"], ["alimenta", "comida"]),
        (["luz", "agua", "gas", "factura", "endesa", "iberdrola", "naturgy"], ["suministro", "luz"]),
        (["fibra", "internet", "movil", "telefono", "movistar", "vodafone", "orange", "digi", "o2", "pepephone", "lowi", "simyo"], ["internet", "movil"]),
        (["gym", "gimnasio"], ["gym", "deporte"]),
        (["farmacia", "dentista", "fisio", "medico"], ["salud"]),
        (["ropa", "zapatos", "zara", "peluqueria"], ["ropa"]),
        (["spotify", "netflix", "icloud", "music", "hbo", "disney", "suscripcion"], ["suscrip"]),
        (["comunidad"], ["comunidad"]),
        (["ahorro", "fondo"], ["ahorro"]),
    ]

    /// Palabras de la nota que se guardan al corregir la partida («dentista» → «Imprevistos»): las vacías no cuentan.
    static func keywords(_ note: String) -> [String] {
        let stop: Set = ["con", "para", "del", "los", "las", "una", "uno", "por", "que", "the"]
        return MD.fold(note.replacingOccurrences(of: #"\[\[[^\]]*\]\]"#, with: " ", options: .regularExpression))
            .split { !$0.isLetter }.map(String.init).filter { $0.count >= 3 && !stop.contains($0) }
    }

    /// Las palabras que vale la pena aprender de una corrección: no las que ya forman parte del nombre de una partida.
    /// Corregir «seguro coche» de «Seguro vida» a «Transporte» aprende «coche»; si aprendiera «seguro», luego
    /// «seguro vida 37» también iría a Transporte, porque lo aprendido manda sobre el nombre.
    static func learnable(_ note: String, categories: [String]) -> [String] {
        let names = Set(categories.flatMap { MD.fold($0).split { !$0.isLetter }.map(String.init) })
        return keywords(note).filter { !names.contains($0) }
    }

    /// Palabras que convierten el importe en una devolución: entra dinero en la partida en vez de salir.
    /// «abono» no está: «abono transporte 20» es el abono mensual, un gasto.
    private static let refundWords = ["devolucion", "devuelto", "devuelta", "devolvieron", "reembolso", "reintegro"]

    static func parse(_ input: String, categories: [String], people: [String] = [], learned: [String: String] = [:], today: Date = DayKey.today()) -> Result? {
        // La fecha va primero: en «22/10 gasolina 40» o «el 12 pan 3» el número de la fecha no es el importe.
        let dated = NaturalDate.extractKind(input.trimmingCharacters(in: .whitespaces), today: today)
        var rest = dated.text
        // «1.200» son mil doscientos (punto de miles), «12,50» y «12.5» llevan decimales.
        // El número empieza en límite de palabra: en «gym o2 40» el importe es 40, no el 2 de «o2».
        // Sin €, un número con céntimos gana a uno entero: en «2 cafés 3,50» el 2 es cuántos, no cuánto.
        guard let m = rest.firstMatch(of: /\b(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d{1,6}(?:[.,]\d{1,2})?)\s*(?:€|eur(?:os)?\b)/)
                ?? rest.firstMatch(of: /(?:€\s*)?\b(\d{1,3}(?:\.\d{3})+,\d{1,2}|\d{1,6}[.,]\d{1,2})\b(?![.,]\d)/)
                ?? rest.firstMatch(of: /(?:€\s*)?\b(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d{1,6}(?:[.,]\d{1,2})?)/) else { return nil }
        var amount = Money.parse(String(m.1))
        guard amount > 0 else { return nil }
        rest.removeSubrange(m.range)
        rest = rest.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if refundWords.contains(where: { MD.fold(rest).contains($0) }) { amount = -amount }
        rest = rest.replacingOccurrences(of: #"^(?i)(en|de|del|por)\s+"#, with: "", options: .regularExpression)
        let folded = " " + MD.fold(rest).replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression) + " "

        // Primero, palabras del propio nombre de la partida («gym», «transporte»): gana la que más comparte y, a igualdad,
        // la de nombre más corto («seguro vida» va a «Seguro vida», no a «Vivienda (…, seguro)»). Después, las pistas.
        let scored = categories.map { c -> (String, Int, Int) in
            let words = MD.fold(c).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 4 || $0.contains(where: \.isNumber) }
            return (c, words.filter { folded.contains(" \($0) ") }.count, words.count)
        }.filter { $0.1 > 0 }
        // Lo aprendido de tus correcciones manda sobre todo lo demás (si la partida sigue existiendo).
        var category = keywords(rest).lazy.compactMap { w in learned[w].flatMap { l in categories.first { MD.fold($0) == MD.fold(l) } } }.first
            ?? scored.max { ($0.1, -$0.2) < ($1.1, -$1.2) }?.0
        if category == nil {
            for h in hints where h.words.contains(where: { folded.contains(" \($0) ") }) {
                if let c = categories.first(where: { c in h.partida.contains { MD.fold(c).contains($0) } }) { category = c; break }
            }
        }
        if category == nil { category = categories.first { MD.fold($0).contains("imprevist") } }

        var person: String?
        for p in people where p.count >= 3 {
            let key = MD.fold(p)
            if folded.contains(" \(key) "), let r = rest.range(of: "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: p) + "(?![\\p{L}\\p{N}])",
                                                                options: [.regularExpression, .caseInsensitive, .diacriticInsensitive]) {
                person = p
                rest.replaceSubrange(r, with: "[[\(p)]]")
                break
            }
        }
        return Result(amount: amount, category: category, note: rest, person: person, date: pastDate(dated.date, kind: dated.kind, today: today) ?? today)
    }

    /// Las fechas de las tareas miran al futuro («el viernes» es el próximo); un gasto ya pasó: «el viernes» es el último,
    /// «22/10» es el de este año y «el 20» el de este mes. «mañana», «en 3 días» o un día de los próximos 7 se respetan
    /// (un pago que se apunta por adelantado).
    private static func pastDate(_ d: Date?, kind: NaturalDate.Kind, today: Date) -> Date? {
        guard let d, d > today else { return d }
        let cal = DayKey.calendar()
        switch kind {
        case .weekday:
            return DayKey.adding(days: -7, to: d)
        case .dayMonth where DayKey.days(from: today, to: d) > 7:
            if let back = cal.date(byAdding: .year, value: -1, to: d), back <= today { return back }
        case .dayOfMonth where DayKey.days(from: today, to: d) > 7:
            // El último día con ese número que ya pasó (saltando meses en que no existe, como el 31).
            let day = cal.component(.day, from: d)
            for k in 0...12 {
                guard let m = cal.date(byAdding: .month, value: -k, to: cal.dateInterval(of: .month, for: today)!.start) else { break }
                if let back = DayKey.make(cal.component(.year, from: m), cal.component(.month, from: m), day), back <= today { return back }
            }
        default: break
        }
        return d
    }
}

// MARK: - Store

extension Store {
    static var gastosFolder: String { VaultPath.gastos }
    func budgetPath(_ month: String) -> String { "\(Store.gastosFolder)/\(month).md" }

    /// Meses con nota de presupuesto, del más viejo al más nuevo.
    var budgetMonths: [String] {
        let prefix = Store.gastosFolder + "/"
        return notes.compactMap { n in
            guard n.path.hasPrefix(prefix), n.name.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
            return n.name
        }.sorted()
    }

    /// Se analiza una vez por recarga: la pantalla de Gastos y los avisos lo piden muchas veces en cada pintado.
    func budget(_ month: String) -> Budget? {
        let p = budgetPath(month)
        if let b = budgetCache[p] { return b }
        guard let t = noteTexts[p] else { return nil }
        let b = Parse.budget(t, month: month, path: p)
        budgetCache[p] = b
        return b
    }

    /// El mes con nota más cercano a `month` (a igual distancia, el siguiente): para no dejar en blanco Inicio,
    /// Finanzas o Gastos cuando el mes actual no tiene nota pero, por ejemplo, el que viene ya está preparado.
    func nearestBudgetMonth(to month: String) -> String? {
        guard let m = BudgetLine.monthIndex(month) else { return nil }
        return budgetMonths.filter { $0 != month }.min { a, b in
            let da = abs((BudgetLine.monthIndex(a) ?? 0) - m), db = abs((BudgetLine.monthIndex(b) ?? 0) - m)
            return da != db ? da < db : a > b
        }
    }

    /// Los `limit` meses con nota anteriores a `month`, del más reciente al más viejo.
    func budgets(before month: String, limit: Int = 3) -> [Budget] {
        budgetMonths.filter { $0 < month }.reversed().prefix(limit).compactMap { budget($0) }
    }

    /// Crea la nota del mes copiando la estructura del último mes que haya.
    @discardableResult
    func createBudget(_ month: String) -> Bool {
        guard budget(month) == nil else { return true }
        // La nota puede existir aunque la app aún no la haya leído (recién llegada de iCloud o sin descargar): no se pisa.
        let u = url(budgetPath(month))
        let placeholder = u.deletingLastPathComponent().appendingPathComponent(".\(u.lastPathComponent).icloud")
        if FileManager.default.fileExists(atPath: u.path) || FileManager.default.fileExists(atPath: placeholder.path) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: u)
            reload()
            if budget(month) != nil { return true }
            message = "La nota \(budgetPath(month)) ya existe pero aún no se puede leer (¿la está descargando iCloud?). No se creó otra."
            return false
        }
        let previous = budgetMonths.last { $0 < month }.flatMap { budget($0) } ?? budgetMonths.last.flatMap { budget($0) }
        return writeNote(budgetPath(month), text: Edit.budgetNote(month: month, from: previous))
    }

    func addExpense(_ amount: Double, category: String, note: String, date: Date) {
        let month = Budget.monthKey(date)
        // Si hay que crear la nota del mes, crearla y apuntar se deshacen juntos: deshacer el gasto no deja una nota vacía.
        grouped {
            guard createBudget(month) else { return }
            edit(budgetPath(month)) { Edit.addBudgetMove($0, date: date, amount: amount, category: category, note: note) }
        }
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
        guard edit(b.path, { Edit.renameBudgetLine($0, line: l.line, from: l.name, to: clean) }) else { return }
        // Lo aprendido apuntaba al nombre viejo: sin esto, «dentista» dejaría de ir a su partida tras renombrarla.
        expenseLearned = expenseLearned.mapValues { MD.fold($0) == MD.fold(l.name) ? clean : $0 }
    }

    func addBudgetIncome(_ b: Budget, name: String) {
        let clean = name.replacingOccurrences(of: "|", with: "/").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        guard !b.incomes.contains(where: { MD.fold($0.name) == MD.fold(clean) }) else { message = "Ya hay un ingreso llamado «\(clean)»."; return }
        edit(b.path) { Edit.addBudgetIncome($0, name: clean) }
    }

    func removeBudgetIncome(_ b: Budget, _ i: BudgetIncome) {
        edit(b.path) { Edit.deleteRow($0, line: i.line, expectFirst: i.name) }
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

    /// Corrige un gasto apuntado. Si la fecha nueva es de otro mes, el gasto se pasa a la nota de ese mes (se deshace de una vez).
    func updateExpense(_ b: Budget, _ m: BudgetMove, date: Date, amount: Double, note: String) {
        let clean = note.trimmingCharacters(in: .whitespaces)
        guard date != m.date || amount != m.amount || clean != m.note else { return }
        if Budget.monthKey(date) == b.month {
            edit(b.path) { Edit.updateBudgetMove($0, month: b.month, move: m, date: date, amount: amount, note: clean) }
            return
        }
        grouped {
            guard createBudget(Budget.monthKey(date)) else { return }
            let before = noteTexts[b.path]
            deleteExpense(b, m)
            // Solo se apunta en el otro mes si de verdad se quitó de este: si no, quedaría duplicado.
            guard noteTexts[b.path] != before else { return }
            addExpense(amount, category: m.category, note: clean, date: date)
        }
    }

    /// Partidas para adivinar un gasto: las del mes en curso, o las del último mes con nota, o las de la hoja de Numbers.
    var expenseCategories: [String] {
        (budget(Budget.monthKey(DayKey.today())) ?? budgetMonths.last.flatMap { budget($0) })?.lines.map(\.name) ?? Edit.defaultBudgetLines.map(\.0)
    }

    /// Palabra → partida, aprendido de las veces que corriges la partida que se adivinó.
    var expenseLearned: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "expenseLearned") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "expenseLearned") }
    }

    func learnExpense(note: String, category: String) {
        let words = ExpenseParser.learnable(note, categories: expenseCategories)
        guard !words.isEmpty else { return }
        var l = expenseLearned
        for w in words { l[w] = category }
        expenseLearned = l
    }

    func parseExpense(_ text: String) -> ExpenseParser.Result? {
        ExpenseParser.parse(text, categories: expenseCategories, people: people.map(\.name), learned: expenseLearned)
    }

    /// Apunta un gasto escrito como frase (⌘K, captura rápida). Sin partida reconocible va a la de imprevistos.
    @discardableResult
    func addExpense(_ p: ExpenseParser.Result) -> String {
        let cats = expenseCategories
        guard let c = p.category ?? cats.first(where: { MD.fold($0).contains("imprevist") }) ?? cats.last else { return "No hay partidas donde apuntarlo." }
        addExpense(p.amount, category: c, note: p.note, date: p.date)
        return (p.amount < 0 ? "Devolución apuntada: \(Money.exact(-p.amount))" : "Apuntado: \(Money.exact(p.amount))") + " en \(c)" + (Budget.monthKey(p.date) != Budget.monthKey(DayKey.today()) ? " (\(Budget.title(Budget.monthKey(p.date)).lowercased()))" : "")
    }

    /// Cambia la partida de un gasto ya apuntado y aprende de la corrección.
    func setExpenseCategory(_ b: Budget, _ m: BudgetMove, to category: String) {
        guard MD.fold(category) != m.key else { return }
        edit(b.path) { text in
            let lines = MD.lines(text)
            guard m.line < lines.count, let first = MD.cells(lines[m.line]).first else { return nil }
            return Edit.setSectionCell(text, section: "Movimientos", line: m.line, expectFirst: first, column: "Partida", value: category)
        }
        learnExpense(note: m.note, category: category)
    }

    /// Pasa el sobrante de un mes al fondo: un movimiento en la partida de ahorro (el último día del mes) y la suma en
    /// `fondo_emergencia_eur` de la nota Finanzas. Así el mes queda cuadrado y el fondo, al día.
    func transferLeftover(_ b: Budget, amount: Double) {
        guard amount > 0, let saving = b.lines.first(where: { $0.kind == .ahorro }), let first = Budget.firstDay(b.month),
              let last = DayKey.calendar().date(byAdding: DateComponents(month: 1, day: -1), to: first) else { return }
        // Los dos cambios se deshacen juntos; si el movimiento no se pudo apuntar, el fondo no se toca.
        grouped {
            guard edit(b.path, { Edit.addBudgetMove($0, date: last, amount: amount, category: saving.name, note: "sobrante del mes") }) else { return }
            guard FileManager.default.fileExists(atPath: url(VaultPath.finanzas).path) else {
                message = "El sobrante se apuntó en \(saving.name), pero no existe \(VaultPath.finanzas) para sumarlo al fondo. Pon lo que tienes en la tarjeta del fondo."
                return
            }
            edit(VaultPath.finanzas) { t in
                let key = "fondo_emergencia_eur"
                let value = Edit.budgetNumber(Money.parse(MD.frontmatter(t)[key] ?? "") + amount)
                // Sin propiedades en la nota, se crean.
                return Edit.setFrontmatter(t, key: key, value: value) ?? "---\n\(key): \(value)\n---\n" + t
            }
        }
    }

    /// Da por pagada la aportación de un evento: la apunta como gasto (con enlace al evento, en la partida que se
    /// adivine por su nombre o en imprevistos) y pone el evento en «pagado». Se deshace de una vez.
    func payContribution(path: String, amount: Double, date: Date = DayKey.today()) {
        guard amount > 0 else { return }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let cats = expenseCategories
        let category = ExpenseParser.parse("\(Edit.budgetNumber(amount)) \(name)", categories: cats, learned: expenseLearned)?.category
            ?? cats.first { MD.fold($0).contains("imprevist") } ?? cats.last
        guard let category else { message = "No hay partidas donde apuntarlo."; return }
        let month = Budget.monthKey(date)
        grouped {
            let before = budget(month)?.moves.count ?? 0
            addExpense(amount, category: category, note: "aportación [[\(name)]]", date: date)
            // Solo se marca pagado si el gasto quedó apuntado.
            guard (budget(month)?.moves.count ?? 0) > before else { return }
            setProperty(path, key: "estado", value: "pagado")
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

// MARK: - Resumen del año

/// Un año de gastos sacado de las notas de cada mes (`Finanzas/Gastos/2026-01.md` … `2026-12.md`): por mes, lo que entró,
/// lo que se gastó y lo que quedó.
struct BudgetYear: Equatable {
    struct Month: Identifiable, Equatable {
        var month: String
        var income: Double
        /// Gastado sin el ahorro: lo apartado sigue siendo tuyo y cuenta en lo que queda. En un mes que aún no ha
        /// empezado, lo previsto (o lo ya pagado, si es más).
        var spent: Double
        /// Mes que aún no ha empezado (nota creada por adelantado): sus cifras son previsión.
        var planned = false
        /// Lo apartado en partidas de ahorro (ya incluido en lo que queda).
        var saved: Double = 0
        var id: String { month }
        var left: Double { income - spent }
        var number: Int { Int(month.suffix(2)) ?? 1 }
        /// Tasa de ahorro: lo que queda sobre lo que entró; `nil` sin ingresos.
        var savingsRate: Double? { income > 0 ? left / income : nil }
    }

    /// Una partida sumada en todo el año. Se junta por nombre sin tildes ni mayúsculas y lleva el nombre del último mes.
    struct Category: Identifiable, Equatable {
        var name: String
        /// `nil` = movimientos con una partida que no está en la tabla de ningún mes.
        var kind: BudgetLine.Kind?
        var planned: Double = 0
        var spent: Double = 0
        var id: String { MD.fold(name) }
        /// Positivo = se gastó más de lo previsto.
        var difference: Double { spent - planned }
    }

    var year: Int
    var months: [Month] = []
    /// Partidas del año, de más a menos gasto. Lo gastado se cuenta igual que en `months`.
    var categories: [Category] = []
    /// El mes en curso, si es de este año: aún no ha acabado.
    var current: String?
    /// Meses con nota que aún no han empezado (creados por adelantado).
    var future: [String] { months.filter(\.planned).map(\.month) }
    /// Meses ya acabados: ni el que está en curso ni los previstos.
    var closed: [Month] { months.filter { $0.month != current && !$0.planned } }

    var income: Double { months.reduce(0) { $0 + $1.income } }
    var spent: Double { months.reduce(0) { $0 + $1.spent } }
    var left: Double { income - spent }
    var saved: Double { months.reduce(0) { $0 + $1.saved } }
    var savingsRate: Double? { income > 0 ? left / income : nil }
    /// Partidas de gasto (sin las de ahorro).
    var expenseCategories: [Category] { categories.filter { $0.kind != .ahorro } }
    /// Gasto medio de los meses ya acabados; `nil` si aún no hay ninguno.
    var averageSpent: Double? {
        let closed = closed
        return closed.isEmpty ? nil : closed.reduce(0) { $0 + $1.spent } / Double(closed.count)
    }

    /// Gasto de los meses acabados frente a los mismos meses (por número) acabados de `previous`; `nil` si no coincide
    /// ninguno o antes no se gastó nada. Comparar años enteros engañaría con un año a medias.
    func spentChange(from previous: BudgetYear) -> (months: [Int], now: Double, before: Double)? {
        let before = Dictionary(previous.closed.map { ($0.number, $0.spent) }, uniquingKeysWith: +)
        let shared = closed.filter { before[$0.number] != nil }
        let then = shared.reduce(0) { $0 + before[$1.number]! }
        guard !shared.isEmpty, then > 0 else { return nil }
        return (shared.map(\.number), shared.reduce(0) { $0 + $1.spent }, then)
    }

    init(year: Int, budgets: [Budget], today: Date = DayKey.today()) {
        self.year = year
        let mine = budgets.filter { $0.month.hasPrefix("\(year)-") }.sorted { $0.month < $1.month }
        let now = Budget.monthKey(today)
        current = mine.contains { $0.month == now } ? now : nil
        // Un mes por venir cuenta lo previsto de cada partida (o lo ya pagado si es más): con lo gastado de verdad,
        // casi nada, sus ingresos inflarían lo que queda.
        months = mine.map { b in
            guard b.month > now else { return Month(month: b.month, income: b.income, spent: b.spent, saved: b.saved) }
            let spent = b.lines.filter { $0.kind != .ahorro }.reduce(b.unassigned) { $0 + max(b.real($1), $1.planned) }
            let saved = b.lines.filter { $0.kind == .ahorro }.reduce(0) { $0 + max(b.real($1), $1.planned) }
            return Month(month: b.month, income: b.income, spent: spent, planned: true, saved: saved)
        }
        var byName: [String: Category] = [:]
        for b in mine {
            let ahead = b.month > now
            for l in b.lines {
                var c = byName[MD.fold(l.name)] ?? Category(name: l.name)
                c.name = l.name; c.kind = l.kind
                c.planned += l.planned
                c.spent += ahead ? max(b.real(l), l.planned) : b.real(l)
                byName[MD.fold(l.name)] = c
            }
            for u in b.unassignedByCategory {
                byName[MD.fold(u.name), default: Category(name: u.name)].spent += u.total
            }
        }
        categories = byName.values.sorted { $0.spent != $1.spent ? $0.spent > $1.spent : $0.name < $1.name }
    }
}

extension Edit {
    /// Nota con el resumen del año: una fila por mes (con enlace a su nota) con ingresos, gastos y lo que queda.
    /// Se rehace cada vez que se guarda con los datos de las notas de cada mes; lo escrito en «Comentarios» se conserva.
    static func budgetYearNote(_ y: BudgetYear, comments: String = "", today: Date = DayKey.today()) -> String {
        var out = ["---", "tipo: resumen-gastos", "año: \(y.year)", "actualizado: \(DayKey.string(today))", "---", "",
                   "# Gastos · Resumen \(y.year)", "", "[[Finanzas]] · se rehace desde la app (Gastos → Año); escribe lo tuyo en Comentarios.", "",
                   "| Mes | Ingresos | Gastos | Queda | % ahorro |", "| :--- | ---: | ---: | ---: | ---: |"]
        for m in y.months {
            out.append(rowString(["[[\(m.month)|\(Budget.title(m.month))]]" + (m.month == y.current ? " (en curso)" : m.planned ? " (previsto)" : ""),
                                  Money.format(m.income), Money.format(m.spent), Money.format(m.left), m.savingsRate.map(Money.percent) ?? "–"]))
        }
        out.append(rowString(["**Total**", Money.format(y.income), Money.format(y.spent), Money.format(y.left), y.savingsRate.map(Money.percent) ?? "–"]))
        var notes: [String] = []
        if let avg = y.averageSpent { notes.append("Gasto medio de los meses acabados: \(Money.format(avg)).") }
        if y.saved > 0 { notes.append("Apartado en partidas de ahorro: \(Money.format(y.saved)) (incluido en lo que queda).") }
        if !notes.isEmpty { out += [""] + notes.map { "- " + $0 } }
        let cats = y.categories.filter { $0.spent != 0 || $0.planned != 0 }
        if !cats.isEmpty {
            out += ["", "## Por partida", "", "| Partida | Tipo | Previsto | Gastado | Diferencia |", "| :--- | :--- | ---: | ---: | ---: |"]
            for c in cats {
                out.append(rowString([c.name, c.kind?.rawValue ?? "Sin partida", c.planned == 0 ? "–" : Money.format(c.planned), Money.format(c.spent),
                                      c.planned == 0 ? "–" : Money.signed(c.difference)]))
            }
        }
        let kept = comments.trimmingCharacters(in: .whitespacesAndNewlines)
        out += ["", "## Comentarios", ""] + (kept.isEmpty ? [] : [kept, ""])
        return out.joined(separator: "\n")
    }

    /// Lo escrito bajo «## Comentarios» en una nota de resumen, hasta el final (con sus propios subtítulos), para no
    /// perderlo al rehacerla.
    static func yearNoteComments(_ text: String) -> String {
        let lines = MD.lines(text)
        guard let i = lines.firstIndex(where: { $0.hasPrefix("## ") && MD.fold($0) == "## comentarios" }) else { return "" }
        return lines[(i + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// El texto sin la fecha de «actualizado»: dos resúmenes con los mismos datos son iguales aunque se hicieran otro día.
    static func withoutUpdateDate(_ text: String) -> String {
        MD.lines(text).filter { !$0.hasPrefix("actualizado:") }.joined(separator: "\n")
    }
}

extension Store {
    /// Años con alguna nota de mes, del más nuevo al más viejo.
    var budgetYears: [Int] { Array(Set(budgetMonths.compactMap { Int($0.prefix(4)) })).sorted(by: >) }

    /// Se calcula una vez por recarga (y por mes de hoy: el mes en curso y los previstos dependen de él).
    func budgetYear(_ year: Int) -> BudgetYear {
        let today = DayKey.today(), key = "\(year)|\(Budget.monthKey(today))"
        if let y = budgetYearCache[key] { return y }
        let y = BudgetYear(year: year, budgets: budgetMonths.filter { $0.hasPrefix("\(year)-") }.compactMap { budget($0) }, today: today)
        budgetYearCache[key] = y
        return y
    }

    func yearSummaryPath(_ year: Int) -> String { "\(Store.gastosFolder)/Resumen \(year).md" }

    private func yearSummaryText(_ year: Int) -> String {
        Edit.budgetYearNote(budgetYear(year), comments: Edit.yearNoteComments(noteTexts[yearSummaryPath(year)] ?? ""))
    }

    /// `nil` si no hay nota del resumen; `true` si tiene lo mismo que se escribiría ahora.
    func yearSummaryIsCurrent(_ year: Int) -> Bool? {
        guard let text = noteTexts[yearSummaryPath(year)] else { return nil }
        return Edit.withoutUpdateDate(text) == Edit.withoutUpdateDate(yearSummaryText(year))
    }

    /// Escribe (o rehace) la nota del resumen del año, conservando sus comentarios. Se deshace con ⌥⌘Z como cualquier cambio.
    @discardableResult
    func writeYearSummary(_ year: Int) -> Bool {
        guard !budgetYear(year).months.isEmpty else { message = "No hay notas de gastos de \(year)."; return false }
        // La nota puede estar en iCloud sin descargar: escribir encima crearía otra y se perderían sus comentarios.
        let path = yearSummaryPath(year), u = url(path)
        if noteTexts[path] == nil, FileManager.default.fileExists(atPath: u.deletingLastPathComponent().appendingPathComponent(".\(u.lastPathComponent).icloud").path) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: u)
            message = "\(path) está en iCloud pero aún no se ha descargado. Prueba otra vez en un momento."
            return false
        }
        // Sin cambios no se escribe: solo movería la fecha y dejaría un paso de deshacer vacío.
        if yearSummaryIsCurrent(year) == true { return true }
        return writeNote(path, text: yearSummaryText(year))
    }
}
