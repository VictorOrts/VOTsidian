import Foundation

// MARK: - Suscripciones: qué se renueva, cuándo y cuánto cuesta al año

struct SuscripcionesData: Equatable {
    enum Status: Equatable { case active, trial, cancelled }

    /// Cada cuánto se cobra.
    enum Period: Equatable {
        case days(Int)
        case weeks(Int)
        case months(Int)

        /// «mensual», «anual», «trimestral», «cada 2 semanas», «3» (meses). Vacío es mensual.
        static func parse(_ text: String) -> Period {
            let t = MD.fold(text)
            if t.isEmpty { return .months(1) }
            let n = min(MD.int(MD.number(t)).map { max(1, $0) } ?? 1, 1200)
            if t.contains("quincen") { return .weeks(2) }
            if t.contains("dia") && !t.contains("mensual") { return .days(n) }
            if t.contains("seman") { return .weeks(n) }
            if t.contains("bimest") { return .months(2) }
            if t.contains("trimest") { return .months(3) }
            if t.contains("semest") { return .months(6) }
            if t.contains("anual") || t.contains("ano") || t.contains("year") { return .months(12 * (t.contains("cada") ? n : 1)) }
            return .months(n)
        }

        var label: String {
            switch self {
            case .days(1): "cada día"
            case .days(let n): "cada \(n) días"
            case .weeks(1): "cada semana"
            case .weeks(let n): "cada \(n) semanas"
            case .months(1): "cada mes"
            case .months(12): "cada año"
            case .months(let n) where n % 12 == 0: "cada \(n / 12) años"
            case .months(let n): "cada \(n) meses"
            }
        }
    }

    struct Item: Identifiable, Equatable {
        var name: String
        var amount: Double
        var period: Period
        /// Un cobro cualquiera de la serie (el último o el próximo). Si la prueba sigue, es el día que acaba.
        var anchor: Date
        var category: String
        var status: Status
        var notes: String
        var line: Int
        var id: Int { line }

        var monthlyCost: Double {
            switch period {
            case .days(let n): amount * 365 / 12 / Double(n)
            case .weeks(let n): amount * 52 / 12 / Double(n)
            case .months(let n): amount / Double(n)
            }
        }
        var yearlyCost: Double { monthlyCost * 12 }

        /// Próximo cobro desde `today` (hoy cuenta). Durante la prueba, el día que acaba. Sin cobros si está cancelada.
        func next(from today: Date = DayKey.today()) -> Date? {
            switch status {
            case .cancelled: return nil
            case .trial: return anchor
            case .active: return occurrence(atOrAfter: today)
            }
        }

        /// Primer cobro de la serie que cae en `day` o después. Se cuenta siempre desde el ancla, así «31 de enero» sigue
        /// siendo fin de mes en febrero y vuelve al 31 en marzo.
        func occurrence(atOrAfter day: Date) -> Date? {
            let cal = DayKey.calendar()
            guard anchor < day else { return anchor }
            switch period {
            case .days(let n), .weeks(let n):
                let step = period == .days(n) ? n : 7 * n
                let k = (DayKey.days(from: anchor, to: day) + step - 1) / step
                return DayKey.adding(days: k * step, to: anchor)
            case .months(let n):
                var k = max(0, (cal.dateComponents([.month], from: anchor, to: day).month ?? 0) / n)
                while let d = cal.date(byAdding: .month, value: k * n, to: anchor) {
                    if d >= day { return d }
                    k += 1
                }
                return nil
            }
        }

        /// Cobros entre `start` y `end`, ambos incluidos (como mucho 400).
        func occurrences(from start: Date, to end: Date) -> [Date] {
            guard status == .active else { return [] }
            var out: [Date] = []
            var from = start
            while out.count < 400, let d = occurrence(atOrAfter: from), d <= end {
                out.append(d)
                from = DayKey.adding(days: 1, to: d)
            }
            return out
        }
    }

    var items: [Item] = []

    var active: [Item] { items.filter { $0.status == .active } }
    var trials: [Item] { items.filter { $0.status == .trial } }
    var monthlyTotal: Double { active.reduce(0) { $0 + $1.monthlyCost } }
    var yearlyTotal: Double { active.reduce(0) { $0 + $1.yearlyCost } }

    /// Activas y pruebas por orden de fecha: lo que toca antes, primero.
    func upcoming(today: Date = DayKey.today()) -> [(item: Item, date: Date)] {
        items.compactMap { i in i.next(from: today).map { (i, $0) } }.sorted { $0.date < $1.date }
    }
}

extension Parse {
    static func suscripciones(_ text: String) -> SuscripcionesData {
        var d = SuscripcionesData()
        for t in tables(text) where t.col("servicio") != nil {
            for r in t.rows {
                let name = t.value(r, "servicio")
                guard !name.isEmpty, let date = DayKey.date(t.value(r, "cobro")) ?? DayKey.dmyDate(t.value(r, "cobro")) else { continue }
                let state = MD.fold(t.value(r, "estado"))
                d.items.append(.init(name: name, amount: Money.parse(t.value(r, "importe")), period: .parse(t.value(r, "cada")), anchor: date,
                                     category: t.value(r, "partida"),
                                     status: state.contains("cancel") || state.contains("baja") ? .cancelled : state.contains("prueba") ? .trial : .active,
                                     notes: t.value(r, "notas"), line: r.line))
            }
        }
        return d
    }
}

extension Edit {
    static func addSuscripcion(_ text: String, name: String, amount: Double, every: String, date: Date, category: String, trial: Bool) -> String? {
        addRow(text, section: "Servicios", cells: [name, Money.exact(amount), every, DayKey.string(date), category, trial ? "Prueba" : "Activa", ""]
            .map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") })
    }

    /// Cambia columnas de una fila de tabla por nombre de columna (sin tildes ni mayúsculas). `expectFirst` evita tocar otra fila
    /// si el archivo cambió. Rellena con celdas vacías las filas más cortas que la cabecera.
    static func setRowValues(_ text: String, line: Int, expectFirst: String, values: [String: String]) -> String? {
        var lines = MD.lines(text)
        guard line >= 0, line < lines.count, MD.isTable(lines[line]), MD.cells(lines[line]).first == expectFirst else { return nil }
        let header = MD.cells(lines[MD.tableHeaderLine(lines, containing: line)])
        var cells = MD.cells(lines[line])
        while cells.count < header.count { cells.append("") }
        for (key, value) in values {
            guard let col = header.firstIndex(where: { MD.fold($0).contains(MD.fold(key)) }) else { return nil }
            cells[col] = value
        }
        lines[line] = rowString(cells)
        return lines.joined(separator: "\n")
    }
}

extension Store {
    func addSuscripcion(name: String, amount: Double, every: String, date: Date, category: String, trial: Bool) {
        edit(VaultPath.suscripciones) { Edit.addSuscripcion($0, name: name, amount: amount, every: every, date: date, category: category, trial: trial) }
    }

    func setSuscripcionStatus(_ i: SuscripcionesData.Item, to status: String) {
        edit(VaultPath.suscripciones) { Edit.setRowValues($0, line: i.line, expectFirst: i.name, values: ["estado": status]) }
    }

    /// Apunta un cobro ya hecho en Gastos (la partida de la fila o la que adivine Gastos). Devuelve la partida usada.
    @discardableResult
    func logSuscripcionCharge(_ i: SuscripcionesData.Item, date: Date = DayKey.today()) -> String? {
        addLinkedExpense(i.amount, note: i.name, date: date, category: i.category, fallback: ["suscrip", "ocio"])
    }

    /// ¿Ya se apuntó en Gastos el cobro de este mes? Solo para lo mensual o más largo; lo semanal o diario se apunta cuando toque.
    func suscripcionLogged(_ i: SuscripcionesData.Item, on day: Date = DayKey.today()) -> Bool {
        guard case .months = i.period else { return false }
        return budget(Budget.monthKey(day))?.moves.contains { MD.fold($0.note) == MD.fold(i.name) && abs($0.amount - i.amount) < 0.005 } ?? false
    }

    /// Lo que se renueva pronto y las pruebas que acaban: 7 días antes (14 si es anual).
    func suscripcionAlerts(today: Date = DayKey.today()) -> [Alert] {
        var out: [Alert] = []
        for (i, date) in suscripciones.upcoming(today: today) {
            let n = DayKey.days(from: today, to: date)
            let price = Money.exact(i.amount)
            if i.status == .trial {
                if n < 0 { out.append(Alert(level: .soon, icon: "repeat", text: "La prueba de \(i.name) terminó \(relativeDays(n)): pásala a Activa o Cancelada", screen: .suscripciones)) }
                else if n <= 7 { out.append(Alert(level: n <= 2 ? .urgent : .soon, icon: "repeat", text: "La prueba de \(i.name) acaba \(relativeDays(n)) (después, \(price))", screen: .suscripciones)) }
            } else {
                let window: Int = if case .months(let m) = i.period, m >= 12 { 14 } else { 7 }
                if n <= window { out.append(Alert(level: n <= 2 ? .soon : .info, icon: "repeat", text: "\(i.name) se renueva \(relativeDays(n)) (\(price))", screen: .suscripciones)) }
            }
        }
        return out
    }
}
