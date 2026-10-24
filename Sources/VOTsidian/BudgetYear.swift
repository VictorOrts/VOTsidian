import Foundation

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
        for m in 1...12 { touch(budgetPath(String(format: "%04d-%02d", year, m))) }   // depende de las notas de sus meses
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
