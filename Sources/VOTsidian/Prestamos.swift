import Foundation

// MARK: - Préstamos y deudas: lo que queda por pagar, la cuota y cuándo se acaba

struct PrestamosData: Equatable {
    struct Loan: Identifiable, Equatable {
        var name: String
        /// Lo que se debía al empezar a apuntar aquí.
        var initial: Double
        /// Cuota mensual; 0 si no hay (una deuda que se paga cuando se puede).
        var installment: Double
        /// Día del mes en que se cobra la cuota.
        var day: Int?
        var until: Date?
        var category: String
        var notes: String
        var line: Int
        var id: Int { line }
    }

    struct Payment: Identifiable, Equatable {
        var date: Date
        var loan: String
        var amount: Double
        var line: Int
        var id: Int { line }
    }

    /// Lo que se ve de un préstamo hoy.
    struct Status: Identifiable, Equatable {
        var loan: Loan
        var paid: Double
        var remaining: Double
        var paidThisMonth: Bool
        /// Próxima cuota (este mes si aún no se pagó y no pasó el día; si no, el mes que viene). `nil` sin cuota, sin día o ya pagado.
        var nextDue: Date?
        /// La cuota de este mes ya pasó y no se apuntó.
        var missed: Bool
        var installmentsLeft: Int?
        var estimatedEnd: Date?
        var id: Int { loan.id }
        var progress: Double { loan.initial > 0 ? min(1, paid / loan.initial) : 0 }
        var isPaidOff: Bool { loan.initial > 0 && remaining <= 0 }
    }

    var loans: [Loan] = []
    var payments: [Payment] = []

    func paid(_ l: Loan) -> Double {
        payments.filter { MD.fold($0.loan) == MD.fold(l.name) }.reduce(0) { $0 + $1.amount }
    }

    func statuses(today: Date = DayKey.today()) -> [Status] {
        let cal = DayKey.calendar()
        let (year, month) = (cal.component(.year, from: today), cal.component(.month, from: today))
        return loans.map { l in
            let paid = paid(l)
            let remaining = max(0, l.initial - paid)
            let thisMonth = payments.contains {
                MD.fold($0.loan) == MD.fold(l.name) && cal.component(.year, from: $0.date) == year && cal.component(.month, from: $0.date) == month
            }
            var next: Date?
            var missed = false
            if l.installment > 0, remaining > 0, let day = l.day {
                func date(_ offset: Int) -> Date? { Self.dueDate(day: day, monthOf: today, plus: offset) }
                if !thisMonth, let d = date(0) {
                    if d >= today { next = d } else { missed = true; next = date(1) }
                } else { next = date(1) }
                if let n = next, let until = l.until, n > until { next = nil }
            }
            let left = l.installment > 0 && remaining > 0 ? Int((remaining / l.installment).rounded(.up)) : nil
            let end = left.flatMap { n in next.flatMap { cal.date(byAdding: .month, value: n - 1, to: $0) } }
            return Status(loan: l, paid: paid, remaining: remaining, paidThisMonth: thisMonth, nextDue: next, missed: missed, installmentsLeft: left, estimatedEnd: end)
        }
    }

    /// El día `day` del mes de `ref` más `offset` meses; si el mes es más corto, su último día.
    static func dueDate(day: Int, monthOf ref: Date, plus offset: Int) -> Date? {
        let cal = DayKey.calendar()
        let c = cal.dateComponents([.year, .month], from: ref)
        guard let first = cal.date(from: DateComponents(year: c.year, month: c.month! + offset, day: 1)),
              let days = cal.range(of: .day, in: .month, for: first)?.count else { return nil }
        let t = cal.dateComponents([.year, .month], from: first)
        return DayKey.make(t.year!, t.month!, min(day, days))
    }

    /// Las cuotas que faltan desde la próxima, una por mes, hasta `end` (como mucho `limit`).
    func dueDates(_ s: Status, upTo end: Date, limit: Int = 60) -> [Date] {
        guard let first = s.nextDue, let day = s.loan.day, let left = s.installmentsLeft else { return [] }
        var out: [Date] = []
        for k in 0..<min(left, limit) {
            guard let d = Self.dueDate(day: day, monthOf: first, plus: k), d <= end, s.loan.until.map({ d <= $0 }) ?? true else { break }
            out.append(d)
        }
        return out
    }

    /// Lo que se debe en total.
    func totalRemaining(today: Date = DayKey.today()) -> Double { statuses(today: today).reduce(0) { $0 + $1.remaining } }
    /// Cuotas mensuales de lo que aún se debe.
    func monthlyInstallments(today: Date = DayKey.today()) -> Double { statuses(today: today).filter { $0.remaining > 0 }.reduce(0) { $0 + $1.loan.installment } }
}

extension Parse {
    static func prestamos(_ text: String) -> PrestamosData {
        var d = PrestamosData()
        for t in tables(text) {
            if t.col("pendiente") != nil {
                for r in t.rows {
                    let name = r.cells.first ?? ""
                    guard !name.isEmpty else { continue }
                    d.loans.append(.init(name: name, initial: Money.parse(t.value(r, "pendiente")), installment: Money.parse(t.value(r, "cuota")),
                                         day: MD.number(t.value(r, "dia")).map { Int($0) }.flatMap { (1...31).contains($0) ? $0 : nil },
                                         until: DayKey.date(t.value(r, "hasta")) ?? DayKey.dmyDate(t.value(r, "hasta")),
                                         category: t.value(r, "partida"), notes: t.value(r, "notas"), line: r.line))
                }
            } else if t.col("fecha") != nil, t.col("importe") != nil {
                for r in t.rows {
                    guard let date = DayKey.date(t.value(r, "fecha")) ?? DayKey.dmyDate(t.value(r, "fecha")) else { continue }
                    d.payments.append(.init(date: date, loan: t.value(r, "prestamo"), amount: Money.parse(t.value(r, "importe")), line: r.line))
                }
            }
        }
        d.payments.sort { $0.date < $1.date }
        return d
    }
}

extension Edit {
    static func addPrestamo(_ text: String, name: String, initial: Double, installment: Double?, day: Int?, until: Date?, category: String) -> String? {
        addRow(text, section: "Lo que debo", cells: [name, Money.exact(initial), installment.map(Money.exact) ?? "", day.map(String.init) ?? "",
                                                  until.map(DayKey.string) ?? "", category, ""]
            .map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") })
    }

    static func addPrestamoPago(_ text: String, date: Date, loan: String, amount: Double, note: String) -> String? {
        addRow(text, section: "Pagos", cells: [DayKey.string(date), loan, Money.exact(amount), note]
            .map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") })
    }
}

extension Store {
    func addPrestamo(name: String, initial: Double, installment: Double?, day: Int?, until: Date?, category: String) {
        edit(VaultPath.prestamos) { Edit.addPrestamo($0, name: name, initial: initial, installment: installment, day: day, until: until, category: category) }
    }

    /// Apunta un pago en la nota y, con `expense`, también en Gastos (se deshacen juntos).
    func addPrestamoPago(_ loan: PrestamosData.Loan, amount: Double, date: Date = DayKey.today(), expense: Bool) {
        grouped {
            guard edit(VaultPath.prestamos, { Edit.addPrestamoPago($0, date: date, loan: loan.name, amount: amount, note: "") }) else { return }
            if expense { addLinkedExpense(amount, note: loan.name, date: date, category: loan.category, fallback: ["prestamo", "deuda", "credito"]) }
        }
    }

    /// La cuota de los próximos 3 días que aún no se apuntó, y las de este mes que se pasaron sin apuntar.
    func prestamoAlerts(today: Date = DayKey.today()) -> [Alert] {
        var out: [Alert] = []
        for s in prestamos.statuses(today: today) {
            if s.missed { out.append(Alert(level: .info, icon: "creditcard.and.123", text: "Cuota de \(s.loan.name) sin apuntar este mes", screen: .prestamos)) }
            if let d = s.nextDue, !s.paidThisMonth {
                let n = DayKey.days(from: today, to: d)
                if n <= 3 { out.append(Alert(level: n <= 1 ? .soon : .info, icon: "creditcard.and.123", text: "Cuota de \(s.loan.name) \(relativeDays(n)) (\(Money.exact(s.loan.installment)))", screen: .prestamos)) }
            }
        }
        return out
    }
}
