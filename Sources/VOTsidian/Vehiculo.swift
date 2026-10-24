import Foundation

// MARK: - Vehículo: fechas que vencen (ITV, seguro…), mantenimiento por km o meses y repostajes

struct VehiculoData: Equatable {
    /// Algo que vence en una fecha: ITV, seguro, impuesto…
    struct Due: Identifiable, Equatable {
        var name: String
        var date: Date
        var line: Int
        var id: Int { line }
    }

    /// Una visita al taller. Con `everyKm` o `everyMonths` se sabe cuándo toca la siguiente.
    struct Service: Identifiable, Equatable {
        var date: Date
        var km: Double?
        var what: String
        var shop: String
        var cost: Double?
        var everyKm: Double?
        var everyMonths: Int?
        var line: Int
        var id: Int { line }
    }

    struct Refuel: Identifiable, Equatable {
        var date: Date
        var km: Double?
        var liters: Double?
        var amount: Double?
        var line: Int
        var id: Int { line }
    }

    /// Próxima vez que toca un mantenimiento: por km, por fecha o por lo que llegue antes.
    struct NextService: Identifiable, Equatable {
        var what: String
        var km: Double?
        var date: Date?
        var kmLeft: Double?
        var daysLeft: Int?
        var id: String { what }
        /// Ya toca (o se pasó) por km o por fecha.
        var isDue: Bool { (kmLeft.map { $0 <= 0 } ?? false) || (daysLeft.map { $0 < 0 } ?? false) }
        /// Falta poco: menos de 1.000 km o de 30 días.
        var isSoon: Bool { !isDue && ((kmLeft.map { $0 <= 1000 } ?? false) || (daysLeft.map { $0 <= 30 } ?? false)) }
    }

    var name = "Vehículo"
    var plate = ""
    /// Km que pone la ficha («km:»); si los registros llevan más, cuentan esos.
    var kmProperty: Double?
    var dues: [Due] = []
    var services: [Service] = []
    var refuels: [Refuel] = []

    /// Los km más altos que se conocen: ficha, taller o repostajes.
    var currentKm: Double? {
        ([kmProperty] + services.map(\.km) + refuels.map(\.km)).compactMap { $0 }.max()
    }

    /// El último registro de cada mantenimiento con intervalo, con lo que falta para el siguiente.
    func nextServices(today: Date = DayKey.today()) -> [NextService] {
        var latest: [String: Service] = [:]
        for s in services where s.everyKm != nil || s.everyMonths != nil {
            let key = MD.fold(s.what)
            if let old = latest[key], old.date > s.date { continue }
            latest[key] = s
        }
        let now = currentKm
        return latest.values.map { s in
            let km = s.everyKm.flatMap { every in s.km.map { $0 + every } }
            let date = s.everyMonths.flatMap { DayKey.calendar().date(byAdding: .month, value: $0, to: s.date) }
            return NextService(what: s.what, km: km, date: date,
                               kmLeft: km.flatMap { k in now.map { k - $0 } }, daysLeft: date.map { DayKey.days(from: today, to: $0) })
        }
        .sorted { a, b in
            if a.isDue != b.isDue { return a.isDue }
            return (a.daysLeft ?? Int.max, a.kmLeft ?? .infinity) < (b.daysLeft ?? Int.max, b.kmLeft ?? .infinity)
        }
    }

    /// Consumo medio en L/100 km, contando de depósito lleno a depósito lleno: los litros del primer repostaje no cuentan.
    var consumption: Double? {
        let r = refuels.filter { $0.km != nil && $0.liters != nil }.sorted { $0.km! < $1.km! }
        guard r.count >= 2, let first = r.first?.km, let last = r.last?.km, last > first else { return nil }
        return r.dropFirst().reduce(0) { $0 + $1.liters! } / (last - first) * 100
    }

    /// Lo gastado en el año en taller y combustible.
    func spent(year: Int) -> (service: Double, fuel: Double) {
        let cal = DayKey.calendar()
        let s = services.filter { cal.component(.year, from: $0.date) == year }.compactMap(\.cost).reduce(0, +)
        let f = refuels.filter { cal.component(.year, from: $0.date) == year }.compactMap(\.amount).reduce(0, +)
        return (s, f)
    }
}

extension Parse {
    static func vehiculo(_ text: String) -> VehiculoData {
        let fm = MD.frontmatter(text)
        var d = VehiculoData()
        d.name = fm["nombre"].flatMap { $0.isEmpty ? nil : $0 } ?? d.name
        d.plate = fm["matricula"] ?? ""
        d.kmProperty = fm["km"].flatMap(Vehiculo.km)
        func date(_ s: String) -> Date? { DayKey.date(s) ?? DayKey.dmyDate(s) }
        for t in tables(text) {
            if t.col("vence") != nil {
                for r in t.rows {
                    let n = r.cells.first ?? ""
                    guard !n.isEmpty, let dt = date(t.value(r, "vence")) else { continue }
                    d.dues.append(.init(name: n, date: dt, line: r.line))
                }
            } else if t.col("litros") != nil {
                for r in t.rows {
                    guard let dt = date(t.value(r, "fecha")) else { continue }
                    d.refuels.append(.init(date: dt, km: Vehiculo.km(t.value(r, "km")), liters: MD.number(t.value(r, "litros")),
                                           amount: Vehiculo.money(t.value(r, "importe")), line: r.line))
                }
            } else if t.col("taller") != nil || MD.fold(t.title).contains("mantenimiento") {
                for r in t.rows {
                    guard let dt = date(t.value(r, "fecha")) else { continue }
                    // «Km» va antes que «Cada (km)»: `col("km")` encuentra la primera.
                    d.services.append(.init(date: dt, km: Vehiculo.km(t.value(r, "km")), what: t.value(r, "qué"), shop: t.value(r, "taller"),
                                            cost: Vehiculo.money(t.value(r, "coste")), everyKm: Vehiculo.km(t.value(r, "cada (km)")),
                                            everyMonths: MD.number(t.value(r, "meses")).map { Int($0) }.flatMap { $0 > 0 ? $0 : nil }, line: r.line))
                }
            }
        }
        d.dues.sort { $0.date < $1.date }
        d.services.sort { $0.date < $1.date }
        d.refuels.sort { $0.date < $1.date }
        return d
    }
}

enum Vehiculo {
    /// Km escritos como «123.456», «123456 km» o «123 456»: el punto y el espacio son de millares, nunca decimales.
    static func km(_ s: String) -> Double? {
        let digits = s.filter(\.isNumber)
        guard let v = Double(digits), v > 0 else { return nil }
        return v
    }

    static func money(_ s: String) -> Double? {
        let v = Money.parse(s)
        return v == 0 ? nil : v
    }

    /// «123.456 km». Siempre con punto de millares (es_ES no lo pone en números de cuatro cifras).
    static func kmText(_ v: Double) -> String {
        var s = String(Int(v.rounded()))
        var i = s.count - 3
        while i > 0 { s.insert(".", at: s.index(s.startIndex, offsetBy: i)); i -= 3 }
        return s + " km"
    }

    /// «en 800 km», «se pasó por 300 km o venció hace 5 días», «en 12 días».
    static func dueText(_ s: VehiculoData.NextService) -> String {
        var parts: [String] = []
        if let k = s.kmLeft { parts.append(k <= 0 ? "se pasó por \(kmText(-k))" : "en \(kmText(k))") }
        if let d = s.daysLeft { parts.append(d < 0 ? "venció \(relativeDays(d))" : relativeDays(d)) }
        if parts.isEmpty, let d = s.date { parts.append("el \(DayKey.dmy(d))") }
        return parts.joined(separator: " o ")
    }
}

extension Edit {
    /// Una fila al final de la tabla de la sección: «Mantenimiento» o «Repostajes».
    static func addVehiculoRow(_ text: String, section: String, cells: [String]) -> String? {
        addRow(text, section: section, cells: cells.map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") })
    }
}

extension Store {
    /// Apunta un repostaje. Con `expense`, también el gasto del mes en Gastos (se deshacen juntos).
    func addRepostaje(date: Date, km: Double?, liters: Double?, amount: Double?, expense: Bool) {
        grouped {
            guard edit(VaultPath.vehiculo, { Edit.addVehiculoRow($0, section: "Repostajes", cells: [
                DayKey.string(date), km.map { String(Int($0)) } ?? "", liters.map { MD.formatNumber($0, comma: true) } ?? "", amount.map(Money.exact) ?? "",
            ]) }) else { return }
            if expense, let amount { addVehiculoExpense(amount, note: "gasolina", date: date) }
        }
    }

    /// Apunta una visita al taller. Con `expense`, también el gasto del mes en Gastos (se deshacen juntos).
    func addMantenimiento(date: Date, km: Double?, what: String, shop: String, cost: Double?, everyKm: Double?, everyMonths: Int?, expense: Bool) {
        grouped {
            guard edit(VaultPath.vehiculo, { Edit.addVehiculoRow($0, section: "Mantenimiento", cells: [
                DayKey.string(date), km.map { String(Int($0)) } ?? "", what, shop, cost.map(Money.exact) ?? "",
                everyKm.map { String(Int($0)) } ?? "", everyMonths.map(String.init) ?? "",
            ]) }) else { return }
            if expense, let cost { addVehiculoExpense(cost, note: "taller " + what, date: date) }
        }
    }

    /// El gasto va a la partida que adivine Gastos para la nota (gasolina, taller → transporte).
    private func addVehiculoExpense(_ amount: Double, note: String, date: Date) {
        addLinkedExpense(amount, note: note, date: date, fallback: ["transporte"])
    }
}
