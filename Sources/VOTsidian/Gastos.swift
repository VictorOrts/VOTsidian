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
    /// Ya va una semana del mes en curso y no hay ni un gasto apuntado: lo normal es que falte apuntarlos, no que no se
    /// haya gastado. Entonces el ritmo y «lo que sobrará» solo repiten lo previsto.
    func nothingLogged(_ s: BudgetStatus) -> Bool {
        s.isCurrent && s.day >= 7 && moves.isEmpty && lines.contains { $0.isDiscretionary && $0.planned > 0 }
    }

    /// Avisos del mes: facturas que suben respecto a la media, partidas que se pasan varios meses seguidos,
    /// aportaciones de eventos sin pagar y lo que sobrará si se sigue al ritmo actual.
    static func insights(_ b: Budget, previous: [Budget], status s: BudgetStatus,
                         events: [(name: String, amount: Double, path: String)] = []) -> [BudgetInsight] {
        var out: [BudgetInsight] = []
        if b.nothingLogged(s) {
            out.append(BudgetInsight(id: "sin-apuntar", level: .warn,
                text: "Llevas \(s.day) días sin apuntar ningún gasto. «Puedes gastar hoy» y lo que sobrará suponen que gastas justo lo previsto. Apúntalos arriba o con la captura rápida (⇧⌘N); vale un total por partida."))
        }
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
        v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
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
        lines.insertClamped(rowString([name] + Array(repeating: "", count: max(width - 1, 0))), at: last.index + 1)
        return lines.joined(separator: "\n")
    }

    /// Añade una partida al final de la tabla de Partidas.
    static func addBudgetLine(_ text: String, name: String, amount: Double, kind: BudgetLine.Kind, every: Int, start: String?) -> String? {
        let t = normalizeBudgetTable(text, section: "Partidas")
        var lines = MD.lines(t)
        guard let r = MD.section(lines, containing: "Partidas"), let last = MD.tableRows(lines).last(where: { r.contains($0.index) }) else { return nil }
        lines.insertClamped(rowString([name, budgetNumber(amount), kind.rawValue, "", "", every > 1 ? String(every) : "", every > 1 ? start ?? "" : ""]), at: last.index + 1)
        return lines.joined(separator: "\n")
    }

    /// Cambia el nombre de una partida y el de sus movimientos, para que sigan contando en ella.
    static func renameBudgetLine(_ text: String, line: Int, from old: String, to new: String) -> String? {
        var lines = MD.lines(text)
        guard line >= 0, line < lines.count, MD.cells(lines[line]).first == old else { return nil }
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
        lines.insertClamped(rowString([DayKey.string(date), budgetNumber(amount), category, note]), at: last.index + 1)
        return lines.joined(separator: "\n")
    }

    /// Cambia fecha, importe y nota de un movimiento, solo si la fila sigue siendo ese movimiento (misma fecha e importe).
    static func updateBudgetMove(_ text: String, month: String, move m: BudgetMove, date: Date, amount: Double, note: String) -> String? {
        guard let now = Parse.budget(text, month: month, path: "").moves.first(where: { $0.line == m.line }), now.date == m.date, now.amount == m.amount else { return nil }
        var t = normalizeBudgetTable(text, section: "Movimientos")
        // Solo lo que cambia: una tabla escrita a mano sin columna «Nota» se puede corregir igual si la nota no se toca.
        let changes = [("Fecha", DayKey.string(date), date != m.date), ("Importe", budgetNumber(amount), amount != m.amount), ("Nota", note, note != m.note)]
        for (column, value, _) in changes.filter(\.2) {
            let current = MD.lines(t)
            guard m.line >= 0, m.line < current.count, let first = MD.cells(current[m.line]).first,
                  let next = setSectionCell(t, section: "Movimientos", line: m.line, expectFirst: first, column: column, value: value) else { return nil }
            t = next
        }
        return t
    }
}
