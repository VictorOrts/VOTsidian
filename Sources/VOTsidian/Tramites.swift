import Foundation

// MARK: - Trámites y seguros: plazos que vuelven cada año (renta, IBI…) y pólizas con su renovación

struct TramitesData: Equatable {
    typealias Period = SuscripcionesData.Period

    /// Un trámite con fecha límite. Sin periodo es de una sola vez.
    struct Procedure: Identifiable, Equatable {
        var name: String
        /// Un plazo de la serie: normalmente el próximo.
        var anchor: Date
        var period: Period?
        var amount: Double?
        /// Cuándo se hizo por última vez.
        var done: Date?
        var notes: String
        var line: Int
        var id: Int { line }

        /// El plazo que falta por cumplir, o `nil` si ya está hecho (uno de una sola vez).
        /// «Hecho» cuenta para el plazo más cercano a esa fecha: la renta presentada en mayo cumple el plazo de junio, y
        /// pagar el IBI unos días tarde cumple el plazo que acaba de pasar, no el del año que viene.
        var pending: Date? {
            guard let period else { return done == nil ? anchor : nil }
            guard let done else { return anchor }
            guard let next = period.index(atOrAfter: done, from: anchor) else { return nil }
            let covered: Int
            if let a = period.date(next - 1, from: anchor), let b = period.date(next, from: anchor) {
                covered = DayKey.days(from: a, to: done) < DayKey.days(from: done, to: b) ? next - 1 : next
            } else { covered = next }
            // Nunca antes del primer plazo apuntado.
            return period.date(max(covered + 1, 0), from: anchor)
        }
    }

    struct Insurance: Identifiable, Equatable {
        var name: String
        var company: String
        var policy: String
        var premium: Double
        var period: Period
        var renewal: Date?
        var phone: String
        var category: String
        var notes: String
        var line: Int
        var id: Int { line }

        var yearlyCost: Double { period.yearly(premium) }

        /// La próxima renovación desde `today` (hoy cuenta).
        func nextRenewal(from today: Date = DayKey.today()) -> Date? {
            guard let renewal else { return nil }
            guard renewal < today else { return renewal }
            return period.index(atOrAfter: today, from: renewal).flatMap { period.date($0, from: renewal) }
        }

        /// Renovaciones entre dos fechas (como mucho 60).
        func renewals(from start: Date, to end: Date) -> [Date] {
            guard let renewal, let first = period.index(atOrAfter: max(start, renewal), from: renewal) else { return [] }
            var out: [Date] = []
            var k = first
            while out.count < 60, let d = period.date(k, from: renewal), d <= end { out.append(d); k += 1 }
            return out
        }
    }

    var procedures: [Procedure] = []
    var insurances: [Insurance] = []

    var yearlyInsurance: Double { insurances.reduce(0) { $0 + $1.yearlyCost } }

    /// Trámites pendientes, el plazo más cercano primero (también los que ya vencieron).
    var pendingProcedures: [(procedure: Procedure, due: Date)] {
        procedures.compactMap { p in p.pending.map { (p, $0) } }.sorted { $0.due < $1.due }
    }
}

extension TramitesData.Period {
    /// Columna «Cada» de un trámite: vacío, «una vez» o «único» es de una sola vez.
    static func parseOptional(_ text: String) -> Self? {
        let t = MD.fold(text)
        if t.isEmpty || t.contains("vez") || t.contains("unic") || t == "-" { return nil }
        return parse(text)
    }
}

extension Parse {
    static func tramites(_ text: String) -> TramitesData {
        var d = TramitesData()
        func date(_ s: String) -> Date? { DayKey.date(s) ?? DayKey.dmyDate(s) }
        for t in tables(text) {
            if t.col("plazo") != nil {
                for r in t.rows {
                    let name = r.cells.first ?? ""
                    guard !name.isEmpty, let anchor = date(t.value(r, "plazo")) else { continue }
                    let amount = Money.parse(t.value(r, "importe"))
                    d.procedures.append(.init(name: name, anchor: anchor, period: .parseOptional(t.value(r, "cada")), amount: amount > 0 ? amount : nil,
                                              done: date(t.value(r, "hecho")), notes: t.value(r, "notas"), line: r.line))
                }
            } else if t.col("prima") != nil {
                for r in t.rows {
                    let name = r.cells.first ?? ""
                    guard !name.isEmpty else { continue }
                    let every = t.value(r, "cada")
                    d.insurances.append(.init(name: name, company: t.value(r, "compañia"), policy: t.value(r, "poliza"), premium: Money.parse(t.value(r, "prima")),
                                              period: every.isEmpty ? .months(12) : .parse(every), renewal: date(t.value(r, "renovacion")),
                                              phone: t.value(r, "telefono"), category: t.value(r, "partida"), notes: t.value(r, "notas"), line: r.line))
                }
            }
        }
        return d
    }
}

extension Edit {
    static func addTramite(_ text: String, name: String, due: Date, every: String, amount: Double?) -> String? {
        addRow(text, section: "Impuestos y plazos", cells: [name, DayKey.string(due), every, amount.map(Money.exact) ?? "", "", ""]
            .map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") })
    }

    static func addSeguro(_ text: String, name: String, company: String, premium: Double, every: String, renewal: Date?, phone: String, category: String) -> String? {
        addRow(text, section: "Pólizas", cells: [name, company, "", Money.exact(premium), every, renewal.map(DayKey.string) ?? "", phone, category, ""]
            .map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") })
    }
}

extension Store {
    func addTramite(name: String, due: Date, every: String, amount: Double?) {
        edit(VaultPath.tramites) { Edit.addTramite($0, name: name, due: due, every: every, amount: amount) }
    }

    func addSeguro(name: String, company: String, premium: Double, every: String, renewal: Date?, phone: String, category: String) {
        edit(VaultPath.tramites) { Edit.addSeguro($0, name: name, company: company, premium: premium, every: every, renewal: renewal, phone: phone, category: category) }
    }

    /// Marca el trámite como hecho hoy y, con `expense`, apunta su importe en Gastos (se deshacen juntos).
    func markTramiteDone(_ p: TramitesData.Procedure, on day: Date = DayKey.today(), expense: Bool) {
        grouped {
            guard edit(VaultPath.tramites, { Edit.setRowValues($0, line: p.line, expectFirst: p.name, values: ["hecho": DayKey.string(day)]) }) else { return }
            if expense, let amount = p.amount { addLinkedExpense(amount, note: p.name, date: day, fallback: ["impuesto", "vivienda", "imprevist"]) }
        }
    }

    /// Apunta en Gastos el pago de la prima. Devuelve la partida usada.
    @discardableResult
    func logSeguroPayment(_ i: TramitesData.Insurance, date: Date = DayKey.today()) -> String? {
        addLinkedExpense(i.premium, note: "Seguro \(i.name)", date: date, category: i.category, fallback: ["seguro", "vivienda"])
    }

    /// ¿Ya se apuntó en Gastos la prima de este periodo? Busca en los meses que dura el periodo hasta `day`.
    func seguroLogged(_ i: TramitesData.Insurance, on day: Date = DayKey.today()) -> Bool {
        let months: Int = if case .months(let n) = i.period { max(1, min(n, 12)) } else { 1 }
        let cal = DayKey.calendar()
        return (0..<months).contains { back in
            guard let d = cal.date(byAdding: .month, value: -back, to: day) else { return false }
            return budget(Budget.monthKey(d))?.moves.contains { MD.fold($0.note) == MD.fold("Seguro \(i.name)") && abs($0.amount - i.premium) < 0.005 } ?? false
        }
    }

    /// Plazos que acaban en 30 días (o ya pasaron) y seguros que se renuevan en 30 días.
    func tramiteAlerts(today: Date = DayKey.today()) -> [Alert] {
        var out: [Alert] = []
        for (p, due) in tramites.pendingProcedures {
            let n = DayKey.days(from: today, to: due)
            if n < 0 { out.append(Alert(level: .urgent, icon: "building.columns", text: "\(p.name): el plazo acabó el \(DayKey.dmy(due))", screen: .tramites)) }
            else if n <= 30 { out.append(Alert(level: n <= 7 ? .soon : .info, icon: "building.columns", text: "\(p.name): plazo \(relativeDays(n)) (\(DayKey.dmy(due)))", screen: .tramites)) }
        }
        for i in tramites.insurances {
            guard let r = i.nextRenewal(from: today) else { continue }
            let n = DayKey.days(from: today, to: r)
            if n <= 30 {
                out.append(Alert(level: n <= 7 ? .soon : .info, icon: "shield.lefthalf.filled",
                                 text: "El seguro de \(i.name) se renueva \(relativeDays(n))" + (i.premium > 0 ? " (\(Money.exact(i.premium)))" : "") + (n > 7 ? ": buen momento para comparar" : ""),
                                 screen: .tramites))
            }
        }
        return out
    }
}
