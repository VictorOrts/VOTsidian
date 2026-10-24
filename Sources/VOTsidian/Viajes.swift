import Foundation

// MARK: - Viajes: fechas, presupuesto, gastos del viaje y lista de equipaje

struct ViajesData: Equatable {
    struct Trip: Identifiable, Equatable {
        var name: String
        var start: Date?
        var end: Date?
        var budget: Double
        var status: String
        var notes: String
        var line: Int
        var id: Int { line }

        /// Hecho o cancelado: ya no cuenta como viaje por venir.
        var isClosed: Bool { let s = MD.fold(status); return s.contains("hecho") || s.contains("cancel") }
        var days: Int? { start.flatMap { s in end.map { DayKey.days(from: s, to: $0) + 1 } } }
    }

    struct Expense: Identifiable, Equatable {
        var date: Date
        var trip: String
        var concept: String
        var amount: Double
        var line: Int
        var id: Int { line }
    }

    struct PackingItem: Identifiable, Equatable {
        var text: String
        var done: Bool
        var raw: String
        var line: Int
        var id: Int { line }
    }

    var trips: [Trip] = []
    var expenses: [Expense] = []
    var packing: [PackingItem] = []

    func spent(_ t: Trip) -> Double { expenses.filter { MD.fold($0.trip) == MD.fold(t.name) }.reduce(0) { $0 + $1.amount } }

    /// Viajes en curso o por venir, el más cercano primero. Los que no tienen fecha van al final.
    func upcoming(today: Date = DayKey.today()) -> [Trip] {
        trips.filter { t in !t.isClosed && (t.end ?? t.start).map { $0 >= today } ?? true }
            .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    func isOngoing(_ t: Trip, today: Date = DayKey.today()) -> Bool {
        guard let s = t.start else { return false }
        return s <= today && (t.end ?? s) >= today
    }
}

extension Parse {
    static func viajes(_ text: String) -> ViajesData {
        var d = ViajesData()
        func date(_ s: String) -> Date? { DayKey.date(s) ?? DayKey.dmyDate(s) }
        for t in tables(text) {
            if t.col("destino") != nil {
                for r in t.rows {
                    let name = t.value(r, "destino")
                    guard !name.isEmpty else { continue }
                    d.trips.append(.init(name: name, start: date(t.value(r, "salida")), end: date(t.value(r, "vuelta")), budget: Money.parse(t.value(r, "presupuesto")),
                                         status: t.value(r, "estado"), notes: t.value(r, "notas"), line: r.line))
                }
            } else if t.col("viaje") != nil, t.col("importe") != nil {
                for r in t.rows {
                    guard let dt = date(t.value(r, "fecha")) else { continue }
                    d.expenses.append(.init(date: dt, trip: t.value(r, "viaje"), concept: t.value(r, "concepto"), amount: Money.parse(t.value(r, "importe")), line: r.line))
                }
            }
        }
        let lines = MD.lines(text)
        if let range = MD.section(lines, containing: "Equipaje") {
            for i in range {
                guard let m = lines[i].firstMatch(of: /^\s*[-*+]\s+\[([ xX])\]\s+(.+)$/) else { continue }
                d.packing.append(.init(text: String(m.2).trimmingCharacters(in: .whitespaces), done: m.1 != " ", raw: lines[i], line: i))
            }
        }
        return d
    }
}

extension Edit {
    static func addViaje(_ text: String, name: String, start: Date?, end: Date?, budget: Double?) -> String? {
        addRow(text, section: "Destinos", cells: [name, start.map(DayKey.string) ?? "", end.map(DayKey.string) ?? "", budget.map(Money.exact) ?? "", "Planeando", ""]
            .map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") })
    }

    static func addViajeGasto(_ text: String, date: Date, trip: String, concept: String, amount: Double) -> String? {
        addRow(text, section: "Gastos del viaje", cells: [DayKey.string(date), trip, concept, Money.exact(amount)]
            .map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") })
    }

    /// Desmarca todas las casillas de la sección.
    static func uncheckSection(_ text: String, section: String) -> String? {
        var lines = MD.lines(text)
        guard let range = MD.section(lines, containing: section) else { return nil }
        for i in range { lines[i] = lines[i].replacingOccurrences(of: #"^(\s*[-*+]\s+\[)[xX](\])"#, with: "$1 $2", options: .regularExpression) }
        return lines.joined(separator: "\n")
    }
}

extension Store {
    func addViaje(name: String, start: Date?, end: Date?, budget: Double?) {
        edit(VaultPath.viajes) { Edit.addViaje($0, name: name, start: start, end: end, budget: budget) }
    }

    func setViajeStatus(_ t: ViajesData.Trip, to status: String) {
        edit(VaultPath.viajes) { Edit.setRowValues($0, line: t.line, expectFirst: t.name, values: ["estado": status]) }
    }

    /// Apunta un gasto del viaje y, con `expense`, también en Gastos (se deshacen juntos).
    func addViajeGasto(_ t: ViajesData.Trip, concept: String, amount: Double, date: Date = DayKey.today(), expense: Bool) {
        grouped {
            guard edit(VaultPath.viajes, { Edit.addViajeGasto($0, date: date, trip: t.name, concept: concept, amount: amount) }) else { return }
            if expense { addLinkedExpense(amount, note: "\(t.name): \(concept)", date: date, fallback: ["viaje", "ocio", "restaurante"]) }
        }
    }

    func addPacking(_ text: String) {
        edit(VaultPath.viajes) { Edit.appendToSection($0, section: "Equipaje", line: "- [ ] \(text)") }
    }
    func togglePacking(_ i: ViajesData.PackingItem) { edit(VaultPath.viajes) { Edit.toggleCheckbox($0, line: i.line, expect: i.raw, completion: false) } }
    func deletePacking(_ i: ViajesData.PackingItem) { edit(VaultPath.viajes) { Edit.deleteLine($0, raw: i.raw, hint: i.line) } }
    func uncheckPacking() { edit(VaultPath.viajes) { Edit.uncheckSection($0, section: "Equipaje") } }

    /// El viaje que se acerca (30 días; 7 si es pronto), el presupuesto pasado y el pasaporte que caduca poco después de salir.
    func viajeAlerts(today: Date = DayKey.today()) -> [Alert] {
        var out: [Alert] = []
        let passports = isVisible(.documentos) ? documents.filter { MD.fold($0.name).contains("pasaporte") } : []
        for t in viajes.upcoming(today: today) {
            if let s = t.start {
                let n = DayKey.days(from: today, to: s)
                if n > 0, n <= 30 { out.append(Alert(level: n <= 7 ? .soon : .info, icon: "airplane", text: "Viaje a \(t.name) \(relativeDays(n))", screen: .viajes)) }
                if n >= 0, n <= 180, let limit = DayKey.calendar().date(byAdding: .month, value: 6, to: s),
                   let p = passports.first(where: { $0.date < limit }) {
                    out.append(Alert(level: .soon, icon: "airplane", text: "El pasaporte caduca el \(DayKey.dmy(p.date)), menos de 6 meses después de salir a \(t.name)", screen: .viajes))
                }
            }
            let spent = viajes.spent(t)
            if t.budget > 0, spent > t.budget {
                out.append(Alert(level: .soon, icon: "airplane", text: "\(t.name): llevas \(Money.exact(spent)) de \(Money.exact(t.budget)) de presupuesto", screen: .viajes))
            }
        }
        return out
    }
}
