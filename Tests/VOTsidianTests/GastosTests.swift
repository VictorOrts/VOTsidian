import Foundation
import Testing
@testable import VOTsidian

private let octubre = """
---
tipo: presupuesto
mes: 2026-10
---

# Gastos · Octubre 2026

## Ingresos
| Concepto | Previsto | Real |
| :--- | ---: | ---: |
| Nómina | 2400 | 2400 |
| Ingresos adicionales | 0 | 150 |

## Partidas
| Partida | Previsto | Tipo | Pagado | Día |
| :--- | ---: | :--- | :---: | ---: |
| Vivienda | 850 | Fijo | ✅ | 1 |
| Alimentación | 350 | Variable |  |  |
| Restaurantes, viajes, entretenimiento | 150 | Variable |  |  |
| Suministros agua y luz | 90 | Fijo |  | 5 |
| Gastos comunidad | 60 | Fijo |  | 28 |
| Ahorro / fondo de emergencia | 300 | Ahorro |  | 28 |

## Movimientos
| Fecha | Importe | Partida | Nota |
| :--- | ---: | :--- | :--- |
| 2026-10-02 | 120 | Alimentación | Mercadona |
| 2026-10-10 | 115,50 | Alimentación | |
| 2026-10-14 | 104 | Suministros agua y luz | luz |
| 2026-10-20 | 160 | Restaurantes, viajes, entretenimiento | cena |

---
[[Finanzas]]
"""

@Test func budgetNoteIsReadAndRealComesFromMoves() throws {
    let b = Parse.budget(octubre, month: "2026-10", path: "Finanzas/Gastos/2026-10.md")
    #expect(b.incomes.count == 2 && b.income == 2550)
    #expect(b.lines.count == 6 && b.moves.count == 4)
    let alim = try #require(b.line(named: "alimentacion"))
    #expect(b.real(alim) == 235.5)
    #expect(b.real(try #require(b.line(named: "Vivienda"))) == 850)          // pagada sin movimientos: lo previsto
    #expect(b.real(try #require(b.line(named: "Gastos comunidad"))) == 0)
    #expect(b.spent == 850 + 235.5 + 160 + 104 && b.saved == 0)
}

@Test func monthStatusProjectsAtCurrentPace() throws {
    let b = Parse.budget(octubre, month: "2026-10", path: "x")
    let s = BudgetStatus(b, today: try #require(DayKey.date("2026-10-20")))
    #expect(s.isCurrent && s.day == 20 && s.days == 31 && s.daysLeft == 12)
    // Variables: 350 + 150 previstos, 235,5 + 160 gastados → quedan 104,5 para 12 días.
    #expect(abs(s.variableLeft - 104.5) < 0.001)
    #expect(abs(s.perDay - 104.5 / 12) < 0.001)
    #expect(abs((s.projection["Restaurantes, viajes, entretenimiento"] ?? 0) - 160 / (20.0 / 31)) < 0.01)
    let series = s.remainingByDay(b)
    #expect(series.real.count == 20 && series.forecast.first?.0 == 20 && series.forecast.last?.0 == 31)
    // El 28 salen comunidad y ahorro.
    let d27 = try #require(series.forecast.first { $0.0 == 27 }?.1), d28 = try #require(series.forecast.first { $0.0 == 28 }?.1)
    #expect(d27 - d28 > 360)

    let past = BudgetStatus(b, today: try #require(DayKey.date("2026-11-05")))
    #expect(!past.isCurrent && past.day == 31 && past.perDay == 0)
}

@Test func newMonthCopiesStructureWithoutRealOrPaid() throws {
    let prev = Parse.budget(octubre, month: "2026-10", path: "x")
    let text = Edit.budgetNote(month: "2026-11", from: prev)
    let b = Parse.budget(text, month: "2026-11", path: "y")
    #expect(b.lines.map(\.name) == prev.lines.map(\.name))
    #expect(b.lines.map(\.planned) == prev.lines.map(\.planned))
    #expect(b.lines.allSatisfy { !$0.paid } && b.moves.isEmpty)
    #expect(b.incomes.allSatisfy { $0.real == nil })
    #expect(b.line(named: "Gastos comunidad")?.day == 28)
    let first = Parse.budget(Edit.budgetNote(month: "2026-10", from: nil), month: "2026-10", path: "z")
    #expect(first.lines.count == Edit.defaultBudgetLines.count && first.lines.contains { $0.kind == .ahorro })
    #expect(!first.lines.contains { MD.fold($0.name).contains("prestamo") || $0.name.contains("O2") })   // genéricas, no las de nadie

    let added = try #require(Edit.addBudgetMove(text, date: DayKey.date("2026-11-03")!, amount: 22.5, category: "Alimentación", note: "pan"))
    let after = Parse.budget(added, month: "2026-11", path: "y")
    #expect(after.moves.count == 1 && after.moves[0].amount == 22.5)
    #expect(added.contains("| 2026-11-03 | 22,50 | Alimentación | pan |"))
    #expect(added.hasSuffix("[[Finanzas]]\n"))
}

@Test func expensePhrasesAreUnderstood() throws {
    let cats = testBudgetLines.map(\.0)
    let today = try #require(DayKey.date("2026-10-23"))
    let a = try #require(ExpenseParser.parse("22 € cena con Ana", categories: cats, people: ["Ana", "Luis"], today: today))
    #expect(a.amount == 22 && a.category == "Restaurantes, viajes, entretenimiento" && a.person == "Ana")
    #expect(a.note == "cena con [[Ana]]" && a.date == today)
    let b = try #require(ExpenseParser.parse("gasolina 48", categories: cats, today: today))
    #expect(b.amount == 48 && b.category == "Transporte" && b.note == "gasolina")
    let c = try #require(ExpenseParser.parse("ayer 12,50 Mercadona", categories: cats, today: today))
    #expect(c.amount == 12.5 && c.category == "Alimentación" && DayKey.string(c.date) == "2026-10-22" && c.note == "Mercadona")
    let d = try #require(ExpenseParser.parse("104 factura de la luz", categories: cats, today: today))
    #expect(d.category == "Suministros agua y luz")
    #expect(ExpenseParser.parse("15 algo raro", categories: cats, today: today)?.category == "Imprevistos / otros")
    #expect(ExpenseParser.parse("gym 55", categories: cats, today: today)?.category == "Gym + O2")
    #expect(ExpenseParser.parse("sin importe", categories: cats, today: today) == nil)
}

@Test func insightsFlagBillsAboveAverageAndRepeatedOverspend() throws {
    func month(_ m: String, luz: Double, rest: Double) -> Budget {
        var b = Parse.budget(Edit.budgetNote(month: m, from: Parse.budget(octubre, month: "2026-10", path: "x")), month: m, path: m)
        b.moves = [BudgetMove(date: DayKey.date(m + "-05")!, amount: luz, category: "Suministros agua y luz", note: "", line: 900),
                   BudgetMove(date: DayKey.date(m + "-10")!, amount: rest, category: "Restaurantes, viajes, entretenimiento", note: "", line: 901)]
        return b
    }
    let cur = Parse.budget(octubre, month: "2026-10", path: "x")
    let prev = [month("2026-09", luz: 90, rest: 190), month("2026-08", luz: 88, rest: 200), month("2026-07", luz: 92, rest: 170)]
    let s = BudgetStatus(cur, today: try #require(DayKey.date("2026-10-20")))
    let ins = Budget.insights(cur, previous: prev, status: s, events: [("Boda Luis y Jazmín", 150, "Finanzas/Boda.md")])
    #expect(ins.contains { $0.id == "sube-Suministros agua y luz" && $0.text.contains("16 %") })
    #expect(ins.contains { $0.id == "pasa-Restaurantes, viajes, entretenimiento" })
    #expect(ins.contains { $0.notePath == "Finanzas/Boda.md" })
}

@MainActor @Test func expensesGoToTheMonthNoteAndCanBeDeleted() throws {
    let store = try undoVault()
    store.addExpense(22, category: "Alimentación", note: "pan", date: try #require(DayKey.date("2026-09-14")))
    let b = try #require(store.budget("2026-09"))
    #expect(b.moves.count == 1 && b.lines.count == 12)
    #expect(store.budgetMonths == ["2026-09"])
    store.setBudgetCell(b, section: "Partidas", line: try #require(b.line(named: "Alimentación")).line, name: "Alimentación", column: "Previsto", value: "350")
    #expect(store.budget("2026-09")?.line(named: "Alimentación")?.planned == 350)
    store.deleteExpense(try #require(store.budget("2026-09")), try #require(store.budget("2026-09")?.moves.first))
    #expect(store.budget("2026-09")?.moves.isEmpty == true)
    // El mes siguiente copia lo previsto.
    store.createBudget("2026-10")
    #expect(store.budget("2026-10")?.line(named: "Alimentación")?.planned == 350)
}

@Test func linesEveryFewMonthsOnlyCountWhenDue() throws {
    let text = """
    ## Partidas
    | Partida | Previsto | Tipo | Pagado | Día | Cada | Desde |
    | :--- | ---: | :--- | :---: | ---: | :---: | :--- |
    | Agua | 60 | Fijo |  | 10 | 2 | 2026-09 |
    | Seguro coche | 180 | Fijo | ✅ | 5 | trimestral | 2026-11 |
    | Vivienda | 850 | Fijo |  | 1 |  |  |
    """
    let oct = Parse.budget(text, month: "2026-10", path: "x")
    let agua = try #require(oct.line(named: "Agua")), seguro = try #require(oct.line(named: "Seguro coche"))
    #expect(agua.every == 2 && !agua.isDue("2026-10") && agua.isDue("2026-11") && agua.isDue("2026-09") && agua.isDue("2027-01"))
    #expect(agua.planned == 0 && agua.amount == 60)
    #expect(seguro.every == 3 && seguro.planned == 0 && !seguro.paid)          // el ✅ de otro mes no cuenta aquí
    #expect(seguro.nextDue(from: "2026-10") == "2026-11" && seguro.isDue("2027-02") && seguro.isDue("2026-08"))
    #expect(oct.planned == 850)
    #expect(seguro.monthlyReserve == 60 && agua.monthlyReserve == 30)
    let nov = Parse.budget(text, month: "2026-11", path: "x")
    #expect(nov.planned == 850 + 60 + 180)

    // El mes nuevo copia frecuencia y mes de inicio.
    let copy = Parse.budget(Edit.budgetNote(month: "2026-12", from: oct), month: "2026-12", path: "y")
    #expect(copy.line(named: "Seguro coche")?.every == 3 && copy.line(named: "Seguro coche")?.start == "2026-11")
    #expect(copy.line(named: "Agua")?.planned == 0 && copy.line(named: "Agua")?.amount == 60)

    // Aviso del mes que viene.
    let s = BudgetStatus(oct, today: try #require(DayKey.date("2026-10-20")))
    #expect(Budget.insights(oct, previous: [], status: s).contains { $0.id == "proximo-mes" && $0.text.contains("Seguro coche") && $0.text.contains("Agua") })
}

@MainActor @Test func frequencyColumnsAreAddedToOldNotes() throws {
    let store = try undoVault()
    store.addExpense(10, category: "Alimentación", note: "", date: try #require(DayKey.date("2026-09-14")))
    // Nota de antes de las frecuencias: sin columnas «Cada» y «Desde».
    let path = store.budgetPath("2026-09")
    store.edit(path) { $0.replacingOccurrences(of: " Cada | Desde |", with: "").replacingOccurrences(of: " :---: | :--- |", with: "")
        .replacingOccurrences(of: #"(\|[^\n]*\|)  \|  \|"#, with: "$1", options: .regularExpression) }
    #expect(!(store.read(path).contains("Cada")))
    let b = try #require(store.budget("2026-09"))
    let seguro = try #require(b.line(named: "Seguros"))
    store.setBudgetFrequency(b, seguro, every: 3, start: "2026-11")
    let after = try #require(store.budget("2026-09")?.line(named: "Seguros"))
    #expect(after.every == 3 && after.start == "2026-11" && after.planned == 0)
    #expect(store.budget("2026-09")?.lines.count == 12 && store.budget("2026-09")?.moves.count == 1)

    // Una fila escrita a mano con menos celdas también se puede marcar como pagada.
    store.edit(path) { $0.replacingOccurrences(of: #"\| Internet y móvil \|[^\n]*"#, with: "| Internet y móvil | 60 | Fijo |", options: .regularExpression) }
    let short = try #require(store.budget("2026-09")?.line(named: "Internet y móvil"))
    store.setBudgetCell(try #require(store.budget("2026-09")), section: "Partidas", line: short.line, name: short.name, column: "Pagado", value: "✅")
    #expect(store.budget("2026-09")?.line(named: "Internet y móvil")?.paid == true)
}

@MainActor @Test func linesCanBeAddedRenamedAndRemoved() throws {
    let store = try undoVault()
    store.addExpense(30, category: "Vivienda (alquiler o hipoteca)", note: "", date: try #require(DayKey.date("2026-11-03")))
    var b = try #require(store.budget("2026-11"))
    store.addBudgetLine(b, name: "Seguro vivienda", amount: 0, kind: .fijo, every: 12, start: "2027-03")
    b = try #require(store.budget("2026-11"))
    let seguro = try #require(b.line(named: "Seguro vivienda"))
    #expect(seguro.every == 12 && seguro.start == "2027-03" && !seguro.isDue("2026-11") && seguro.isDue("2027-03") && seguro.isDue("2028-03"))
    store.addBudgetLine(b, name: "seguro vivienda", amount: 0, kind: .fijo, every: 1, start: nil)
    #expect(store.budget("2026-11")?.lines.count == 13 && store.message?.contains("Ya hay") == true)

    let viv = try #require(b.line(named: "Vivienda (alquiler o hipoteca)"))
    store.renameBudgetLine(b, viv, to: "Vivienda (alquiler, hipoteca, impuestos)")
    b = try #require(store.budget("2026-11"))
    let renamed = try #require(b.line(named: "Vivienda (alquiler, hipoteca, impuestos)"))
    #expect(b.real(renamed) == 30 && b.unassigned == 0)

    store.removeBudgetLine(b, try #require(b.line(named: "Internet y móvil")))
    #expect(store.budget("2026-11")?.line(named: "Internet y móvil") == nil && store.budget("2026-11")?.lines.count == 12)
}

@Test func reviewFixesForExpenses() throws {
    let today = try #require(DayKey.date("2026-10-23"))
    let cats = testBudgetLines.map(\.0) + ["Seguro vivienda"]
    // La fecha no se toma por importe; si hay varios números, gana el que lleva €.
    let a = try #require(ExpenseParser.parse("22/10 gasolina 40", categories: cats, today: today))
    #expect(a.amount == 40 && DayKey.string(a.date) == "2026-10-22" && a.category == "Transporte")
    #expect(ExpenseParser.parse("2 cafés 3,50 €", categories: cats, today: today)?.amount == 3.5)
    // Gana la partida que más palabras comparte y, a igualdad, la de nombre más corto.
    #expect(ExpenseParser.parse("seguro vida 37", categories: cats, today: today)?.category == "Seguro vida")
    #expect(ExpenseParser.parse("seguro vivienda 280", categories: cats, today: today)?.category == "Seguro vivienda")
    #expect(ExpenseParser.parse("alquiler 525", categories: cats, today: today)?.category == "Vivienda (alquiler, hipoteca, impuestos, seguro)")
    #expect(Money.exact(12.5).hasPrefix("12,50") && Money.exact(12) == Money.format(12))
    // 2026-10-23 es viernes: «el martes» es el martes pasado, no el que viene.
    #expect(ExpenseParser.parse("el martes cine 9", categories: cats, today: today).map { DayKey.string($0.date) } == "2026-10-20")
    #expect(ExpenseParser.parse("mañana comunidad 60", categories: cats, today: today).map { DayKey.string($0.date) } == "2026-10-24")

    // «Puedes gastar hoy» no promete más de lo que queda tras los fijos.
    let short = """
    ## Ingresos
    | Concepto | Previsto | Real |
    | :--- | ---: | ---: |
    | Nómina | 1000 | 1000 |

    ## Partidas
    | Partida | Previsto | Tipo | Pagado | Día |
    | :--- | ---: | :--- | :---: | ---: |
    | Alquiler | 900 | Fijo | ✅ | 1 |
    | Comida | 400 | Variable |  |  |

    ## Movimientos
    | Fecha | Importe | Partida | Nota |
    | :--- | ---: | :--- | :--- |
    | 2026-10-05 | 50 | Comida | |
    """
    let s = BudgetStatus(Parse.budget(short, month: "2026-10", path: "x"), today: today)
    #expect(s.variableLeft == 50 && abs(s.perDay - 50.0 / 9) < 0.001)

    // Renombrar funciona aunque la nota no tenga tabla de movimientos.
    let noMoves = "## Partidas\n| Partida | Previsto |\n| :--- | ---: |\n| Luz | 90 |\n"
    #expect(Edit.renameBudgetLine(noMoves, line: 3, from: "Luz", to: "Electricidad")?.contains("| Electricidad | 90 |") == true)
}

@Test func secondReviewOfExpenses() throws {
    let today = try #require(DayKey.date("2026-10-23"))
    let cats = testBudgetLines.map(\.0)
    #expect(ExpenseParser.parse("1.200 € alquiler", categories: cats, today: today)?.amount == 1200)
    #expect(ExpenseParser.parse("alquiler 1.250,50", categories: cats, today: today)?.amount == 1250.5)
    #expect(ExpenseParser.parse("pan 2.5", categories: cats, today: today)?.amount == 2.5)
    let p = try #require(ExpenseParser.parse("3 € banana con Ana", categories: cats, people: ["Ana"], today: today))
    #expect(p.note == "banana con [[Ana]]")

    let every = "## Partidas\n| Partida | Previsto | Tipo | Pagado | Día | Cada | Desde |\n| :--- | ---: | :--- | :---: | ---: | :---: | :--- |\n| ITV | 40 | Fijo |  |  | cada 2 años | 2026-10 |\n| Seguro | 300 | Fijo |  |  | anual | 2026-10 |\n"
    let b = Parse.budget(every, month: "2026-10", path: "x")
    #expect(b.line(named: "ITV")?.every == 24 && b.line(named: "Seguro")?.every == 12)

    // El último punto de la gráfica es lo mismo que «Sobrará», también con un fijo a medio pagar y un gasto de otro mes.
    var oct = Parse.budget(octubre, month: "2026-10", path: "x")
    oct.moves.append(BudgetMove(date: try #require(DayKey.date("2026-10-15")), amount: 30, category: "Gastos comunidad", note: "", line: 990))
    oct.moves.append(BudgetMove(date: try #require(DayKey.date("2026-09-30")), amount: 12, category: "Alimentación", note: "", line: 991))
    for day in ["2026-10-02", "2026-10-20"] {
        let s = BudgetStatus(oct, today: try #require(DayKey.date(day)))
        let end = try #require(s.remainingByDay(oct).forecast.last?.1)
        #expect(abs(end - s.endLeft) < 0.01, "día \(day): gráfica \(end) frente a \(s.endLeft)")
    }
}

@Test func everyFewMonthsVariableIsNotDailySpending() throws {
    let text = """
    ## Ingresos
    | Concepto | Previsto | Real |
    | :--- | ---: | ---: |
    | Nómina | 2000 | 2000 |

    ## Partidas
    | Partida | Previsto | Tipo | Pagado | Día | Cada | Desde |
    | :--- | ---: | :--- | :---: | ---: | :---: | :--- |
    | Comida | 300 | Variable |  |  |  |  |
    | Comunidad | 500 | Variable |  |  | 3 | 2026-10 |
    """
    let b = Parse.budget(text, month: "2026-10", path: "x")
    let s = BudgetStatus(b, today: try #require(DayKey.date("2026-10-10")))
    // Los 500 € de la comunidad no son «gasto libre»: no entran en lo que se puede gastar al día.
    #expect(s.variableLeft == 300 && s.projection["Comunidad"] == nil)
    #expect(abs(s.endLeft - (2000 - 500 - 300)) < 0.01)
    #expect(!(try #require(b.line(named: "Comunidad"))).isDiscretionary)
}

@Test func learnedCorrectionsWinAndQuickCommandAddsExpenses() throws {
    let cats = testBudgetLines.map(\.0)
    let today = try #require(DayKey.date("2026-10-23"))
    #expect(ExpenseParser.parse("40 dentista", categories: cats, today: today)?.category == "Imprevistos / otros")
    let learned = Dictionary(uniqueKeysWithValues: ExpenseParser.keywords("dentista").map { ($0, "Seguro vida") })
    #expect(ExpenseParser.parse("40 dentista", categories: cats, learned: learned, today: today)?.category == "Seguro vida")
    #expect(ExpenseParser.keywords("cena con [[Ana]] en el bar") == ["cena", "bar"])
    guard case .expense(let p)? = QuickCommand.parse("gasto 22 € cena con Ana", today: today, categories: cats, people: ["Ana"]) else {
        Issue.record("«gasto …» no se entiende"); return
    }
    #expect(p.amount == 22 && p.category == "Restaurantes, viajes, entretenimiento" && p.note == "cena con [[Ana]]")
}

@MainActor @Test func leftoverGoesToTheFundAndAlertsForPayments() throws {
    let store = try undoVault()
    try "---\ntipo: hub\nfondo_emergencia_eur: 1000\n---\n# Finanzas\n".write(to: store.url(VaultPath.finanzas).deletingLastPathComponent().appendingPathComponent("Finanzas.md").creatingParent(), atomically: true, encoding: .utf8)
    store.reload()
    store.addExpense(100, category: "Alimentación", note: "", date: try #require(DayKey.date("2026-09-10")))
    var b = try #require(store.budget("2026-09"))
    let nomina = try #require(b.incomes.first)
    store.setBudgetCell(b, section: "Ingresos", line: nomina.line, name: nomina.name, column: "Real", value: "500")
    b = try #require(store.budget("2026-09"))
    let s = BudgetStatus(b, today: try #require(DayKey.date("2026-10-05")))
    let ins = Budget.insights(b, previous: [], status: s)
    let close = try #require(ins.first { $0.id.hasPrefix("cierre") })
    #expect(close.transfer == 400)
    store.transferLeftover(b, amount: 400)
    let after = try #require(store.budget("2026-09"))
    #expect(after.saved == 400 && after.income - after.spent - after.saved == 0)
    #expect(store.noteMeta[VaultPath.finanzas]?["fondo_emergencia_eur"] == "1400")

    // Avisos: un pago con día pasado sin marcar, y el de mañana.
    store.addExpense(5, category: "Alimentación", note: "", date: try #require(DayKey.date("2026-10-02")))
    var oct = try #require(store.budget("2026-10"))
    for (name, day) in [("Suscripciones", "1"), ("Seguros", "6")] {
        let l = try #require(oct.line(named: name))
        store.setBudgetCell(oct, section: "Partidas", line: l.line, name: name, column: "Previsto", value: "50")
        oct = try #require(store.budget("2026-10"))
        store.setBudgetCell(oct, section: "Partidas", line: l.line, name: name, column: "Día", value: day)
        oct = try #require(store.budget("2026-10"))
    }
    let alerts = store.budgetAlerts(today: try #require(DayKey.date("2026-10-05"))).map(\.text)
    #expect(alerts.contains { $0.contains("Suscripciones") && $0.contains("sin marcar") })
    #expect(alerts.contains { $0.contains("Mañana se paga Seguros") })
}

extension URL {
    /// Crea la carpeta del archivo y devuelve el mismo URL, para escribir en una ruta nueva en una sola línea.
    func creatingParent() throws -> URL {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}

@MainActor @Test func alertActionsAndPaymentReminders() throws {
    let store = try undoVault()
    let today = try #require(DayKey.date("2026-10-05"))
    store.addExpense(5, category: "Alimentación", note: "", date: try #require(DayKey.date("2026-10-02")))
    var oct = try #require(store.budget("2026-10"))
    for (name, day) in [("Suscripciones", "1"), ("Seguros", "20")] {
        let l = try #require(oct.line(named: name))
        store.setBudgetCell(oct, section: "Partidas", line: l.line, name: name, column: "Previsto", value: "50")
        oct = try #require(store.budget("2026-10"))
        store.setBudgetCell(oct, section: "Partidas", line: l.line, name: name, column: "Día", value: day)
        oct = try #require(store.budget("2026-10"))
    }
    // «Pagado» desde el aviso marca la partida.
    let gym = try #require(store.budgetAlerts(today: today).first { $0.text.contains("Suscripciones") })
    #expect(gym.action == .markPaid(month: "2026-10", line: try #require(oct.line(named: "Suscripciones")).line, name: "Suscripciones"))
    #expect(store.perform(try #require(gym.action)))
    #expect(store.budget("2026-10")?.line(named: "Suscripciones")?.paid == true)
    #expect(!store.budgetAlerts(today: today).contains { $0.text.contains("Suscripciones") })

    // Recordatorios: el seguro de este mes (20 oct) y los dos del mes que viene, aunque noviembre no tenga nota.
    let pays = store.upcomingPayments(today: today).map { "\($0.name) \(DayKey.string($0.date))" }
    #expect(pays == ["Seguros 2026-10-20", "Suscripciones 2026-11-01", "Seguros 2026-11-20"])
    let events = ICS.events(ReminderSources(payments: store.upcomingPayments(today: today)), plan: ReminderPlan(), today: today)
    let pay = try #require(events.first { $0.uid.hasPrefix("pago-") })
    #expect(pay.title.hasPrefix("Pagar: Seguros") && pay.extraTriggers == ["-P1D"])
    #expect(Notifier.plan([pay], now: today, today: today).contains { $0.body.hasPrefix("Mañana.") })
    var off = ReminderPlan(); off.payments = false
    #expect(!ICS.events(ReminderSources(payments: store.upcomingPayments(today: today)), plan: off, today: today).contains { $0.uid.hasPrefix("pago-") })
}

@Test func todaysSpendingLowersWhatIsLeftForToday() throws {
    let b = Parse.budget(octubre, month: "2026-10", path: "x")
    // El 20 hay 160 € de restaurantes apuntados ese mismo día.
    let s = BudgetStatus(b, today: try #require(DayKey.date("2026-10-20")))
    #expect(s.spentToday == 160)
    #expect(abs(s.todayAllowance - (104.5 + 160) / 12) < 0.001 && s.leftToday == 0)
    // Sin nada hoy, lo de hoy es el reparto de siempre.
    let s21 = BudgetStatus(b, today: try #require(DayKey.date("2026-10-21")))
    #expect(s21.spentToday == 0 && abs(s21.leftToday - s21.perDay) < 0.001)
    #expect(BudgetStatus(b, today: try #require(DayKey.date("2026-11-05"))).leftToday == 0)
}

@Test func paidBeforeItsDayIsAlreadyGone() throws {
    // Comunidad (día 28) marcada como pagada el 20: «Hoy quedan» ya no la cuenta, y el final del mes no cambia.
    let text = octubre.replacingOccurrences(of: "| Gastos comunidad | 60 | Fijo |  | 28 |", with: "| Gastos comunidad | 60 | Fijo | ✅ | 28 |")
    let b = Parse.budget(text, month: "2026-10", path: "x")
    let s = BudgetStatus(b, today: try #require(DayKey.date("2026-10-20")))
    let series = s.remainingByDay(b)
    let base = BudgetStatus(Parse.budget(octubre, month: "2026-10", path: "x"), today: try #require(DayKey.date("2026-10-20")))
    let before = try #require(base.remainingByDay(Parse.budget(octubre, month: "2026-10", path: "x")).real.last?.1)
    #expect(abs((series.real.last?.1 ?? 0) - (before - 60)) < 0.01)
    #expect(abs((series.forecast.last?.1 ?? 0) - s.endLeft) < 0.01)
}

@Test func fundGoalUsesATypicalMonthAndClosingSkipsUnpaidBills() throws {
    let text = """
    ## Ingresos
    | Concepto | Previsto | Real |
    | :--- | ---: | ---: |
    | Nómina | 2000 | 2000 |

    ## Partidas
    | Partida | Previsto | Tipo | Pagado | Día | Cada | Desde |
    | :--- | ---: | :--- | :---: | ---: | :---: | :--- |
    | Alquiler | 800 | Fijo | ✔ | 1 |  |  |
    | Luz | 90 | Fijo |  | 5 |  |  |
    | Seguro coche | 360 | Fijo |  |  | anual | 2027-03 |
    | Comida | 300 | Variable |  |  |  |  |
    | Ahorro | 200 | Ahorro |  |  |  |  |

    ## Movimientos
    | Fecha | Importe | Partida | Nota |
    | :--- | ---: | :--- | :--- |
    | 2026-10-04 | 250 | Comida | |
    | 2026-10-09 | 12 | Farmacia | |
    | 2026-10-11 | 8 | farmacia | |
    """
    let b = Parse.budget(text, month: "2026-10", path: "x")
    #expect(b.line(named: "Alquiler")?.paid == true)
    // 800 + 90 + 360/12 + 300: el seguro anual cuenta 30 € aunque este mes no toque.
    #expect(b.plannedExpenses == 1190 && b.typicalMonthExpenses == 1220)
    #expect(b.unpaidFixed.map(\.name) == ["Luz"])
    #expect(b.unassignedByCategory.count == 1 && b.unassignedByCategory[0].total == 20)

    let closed = BudgetStatus(b, today: try #require(DayKey.date("2026-11-03")))
    let ins = Budget.insights(b, previous: [], status: closed)
    #expect(ins.contains { $0.id.hasPrefix("sin-marcar") && $0.text.contains("Luz") })
    // 2000 − (800 + 250 + 20) − 0 ahorrado − 90 de la luz sin marcar.
    #expect(ins.first { $0.id.hasPrefix("cierre") }?.transfer == 840)
    #expect(ins.first { $0.id.hasPrefix("cierre") }?.month == "2026-10")
}

@Test func thirdReviewOfExpensePhrases() throws {
    let today = try #require(DayKey.date("2026-10-23"))
    let cats = testBudgetLines.map(\.0)
    let a = try #require(ExpenseParser.parse("€12 pan", categories: cats, today: today))
    #expect(a.amount == 12 && a.note == "pan")
    #expect(ExpenseParser.parse("2 cafés 3,50", categories: cats, today: today)?.amount == 3.5)
    #expect(ExpenseParser.parse("alquiler 1.250,50", categories: cats, today: today)?.amount == 1250.5)
    #expect(ExpenseParser.parse("1.200 alquiler", categories: cats, today: today)?.amount == 1200)
    #expect(ExpenseParser.parse("gym o2 40", categories: cats, today: today)?.amount == 40)
    let r = try #require(ExpenseParser.parse("devolución 30 Zara", categories: cats, today: today))
    #expect(r.amount == -30 && r.note == "devolución Zara")
    guard case .expense(let q)? = QuickCommand.parse("reembolso 15,20 Amazon", today: today, categories: cats) else {
        Issue.record("«reembolso …» no se entiende"); return
    }
    #expect(q.amount == -15.2 && QuickCommand.expense(q).summary.hasPrefix("Devolución de 15,20"))

    // Al corregir no se aprenden las palabras que ya son de una partida.
    #expect(ExpenseParser.learnable("seguro coche", categories: cats) == ["coche"])
    let learned = Dictionary(uniqueKeysWithValues: ExpenseParser.learnable("seguro coche", categories: cats).map { ($0, "Transporte") })
    #expect(ExpenseParser.parse("seguro vida 37", categories: cats, learned: learned, today: today)?.category == "Seguro vida")
    #expect(ExpenseParser.parse("seguro coche 300", categories: cats, learned: learned, today: today)?.category == "Transporte")
}

@MainActor @Test func expensesCanBeCorrectedAndMovedToAnotherMonth() throws {
    let store = try undoVault()
    store.addExpense(22, category: "Alimentación", note: "pan", date: try #require(DayKey.date("2026-10-14")))
    var b = try #require(store.budget("2026-10"))
    store.updateExpense(b, try #require(b.moves.first), date: try #require(DayKey.date("2026-10-15")), amount: 25.5, note: "pan y leche")
    b = try #require(store.budget("2026-10"))
    let m = try #require(b.moves.first)
    #expect(b.moves.count == 1 && m.amount == 25.5 && m.note == "pan y leche" && DayKey.string(m.date) == "2026-10-15")

    // A otro mes: sale de octubre, entra en septiembre, y se deshace de una vez.
    store.updateExpense(b, m, date: try #require(DayKey.date("2026-09-30")), amount: 25.5, note: "pan y leche")
    #expect(store.budget("2026-10")?.moves.isEmpty == true)
    #expect(store.budget("2026-09")?.moves.first?.amount == 25.5)
    store.undo()
    #expect(store.message == nil, "\(store.message ?? "")")
    #expect(store.budget("2026-10")?.moves.count == 1, "\(store.read(store.budgetPath("2026-10")))")
    #expect(store.budget("2026-09")?.moves.isEmpty != false)

    // Un movimiento que ya cambió en la nota no se toca.
    let stale = BudgetMove(date: m.date, amount: 99, category: m.category, note: "", line: m.line)
    store.updateExpense(try #require(store.budget("2026-10")), stale, date: m.date, amount: 1, note: "")
    #expect(store.budget("2026-10")?.moves.first?.amount == 25.5)
}

@MainActor @Test func renamingALineKeepsWhatWasLearned() throws {
    let store = try undoVault()
    let saved = store.expenseLearned
    defer { store.expenseLearned = saved }
    store.addExpense(40, category: "Imprevistos / otros", note: "dentista", date: try #require(DayKey.date("2026-10-14")))
    store.expenseLearned = ["dentista": "Imprevistos / otros"]
    let b = try #require(store.budget("2026-10"))
    store.renameBudgetLine(b, try #require(b.line(named: "Imprevistos / otros")), to: "Salud")
    #expect(store.expenseLearned["dentista"] == "Salud")
}

@MainActor @Test func expensesAreExportedToCSV() throws {
    let store = try undoVault()
    store.addExpense(12.5, category: "Alimentación", note: "pan, leche", date: try #require(DayKey.date("2026-10-14")))
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
    let files = try store.exportData(to: out)
    let csv = try String(contentsOf: try #require(files.first { $0.lastPathComponent == "gastos.csv" }), encoding: .utf8)
    #expect(csv == "mes,fecha,importe_eur,partida,nota\n2026-10,2026-10-14,12.5,Alimentación,\"pan, leche\"\n")
}

@MainActor @Test func firstExpenseOfAMonthUndoesInOneStep() throws {
    let store = try undoVault()
    store.addExpense(9, category: "Transporte", note: "metro", date: try #require(DayKey.date("2026-12-02")))
    #expect(store.budget("2026-12")?.moves.count == 1)
    store.undo()
    #expect(store.message == nil && store.budget("2026-12") == nil && !store.canUndo)
}

@MainActor @Test func yearSummaryShowsIncomeSpentAndLeftPerMonth() throws {
    let store = try undoVault()
    store.addExpense(100, category: "Alimentación", note: "", date: try #require(DayKey.date("2026-09-10")))
    store.addExpense(40, category: "Transporte", note: "", date: try #require(DayKey.date("2026-10-03")))
    for month in ["2026-09", "2026-10"] {
        let b = try #require(store.budget(month)), nomina = try #require(b.incomes.first)
        store.setBudgetCell(b, section: "Ingresos", line: nomina.line, name: nomina.name, column: "Real", value: "1000")
    }
    // El ahorro no es gasto: queda en lo que queda.
    let oct = try #require(store.budget("2026-10"))
    store.addExpense(200, category: try #require(oct.lines.first { $0.kind == .ahorro }).name, note: "", date: try #require(DayKey.date("2026-10-05")))

    let y = BudgetYear(year: 2026, budgets: store.budgetMonths.compactMap { store.budget($0) }, today: try #require(DayKey.date("2026-10-23")))
    #expect(y.months.map(\.month) == ["2026-09", "2026-10"] && y.current == "2026-10")
    #expect(y.months.map(\.spent) == [100, 40] && y.months.map(\.left) == [900, 960])
    #expect(y.income == 2000 && y.spent == 140 && y.left == 1860)
    #expect(store.budgetYears == [2026] && store.budgetYear(2025).months.isEmpty)

    let note = Edit.budgetYearNote(y, today: try #require(DayKey.date("2026-10-23")))
    #expect(note.contains("| Mes | Ingresos | Gastos | Queda | % ahorro |"))
    #expect(note.contains("| **Total** | \(Money.format(2000)) | \(Money.format(140)) | \(Money.format(1860)) | 93 % |"))
    #expect(note.contains("| [[2026-09\\|Septiembre de 2026]] |"))
    #expect(store.writeYearSummary(2026) && store.noteTexts[store.yearSummaryPath(2026)] != nil)
    // La nota del resumen no se toma por un mes.
    #expect(store.budgetMonths == ["2026-09", "2026-10"])
    #expect(!store.writeYearSummary(2024) && store.message?.contains("2024") == true)
}

@MainActor @Test func yearSummaryKeepsCommentsSkipsFutureMonthsAndKnowsWhenItIsStale() throws {
    let store = try undoVault()
    // Junio y julio ya acabaron; diciembre de 2027 está creado por adelantado y sale con lo previsto.
    store.addExpense(100, category: "Alimentación", note: "", date: try #require(DayKey.date("2026-06-10")))
    store.addExpense(300, category: "Alimentación", note: "", date: try #require(DayKey.date("2026-07-10")))
    store.createBudget("2027-12")
    let y = BudgetYear(year: 2026, budgets: store.budgetMonths.compactMap { store.budget($0) }, today: try #require(DayKey.date("2026-07-20")))
    #expect(y.months.map(\.month) == ["2026-06", "2026-07"] && y.current == "2026-07" && y.averageSpent == 100)
    #expect(BudgetYear(year: 2027, budgets: store.budgetMonths.compactMap { store.budget($0) }, today: try #require(DayKey.date("2026-07-20"))).future == ["2027-12"])

    #expect(store.yearSummaryIsCurrent(2026) == nil)
    #expect(store.writeYearSummary(2026) && store.yearSummaryIsCurrent(2026) == true)
    // Escribir otra vez sin cambios no deja otro paso de deshacer.
    let steps = store.undoStack.count
    #expect(store.writeYearSummary(2026) && store.undoStack.count == steps)

    // Lo escrito en Comentarios (con subtítulos) sobrevive al rehacer la nota.
    let path = store.yearSummaryPath(2026)
    store.edit(path) { $0 + "Año de mudanza.\n\n### Para 2027\n- gastar menos fuera\n" }
    store.addExpense(50, category: "Transporte", note: "", date: try #require(DayKey.date("2026-07-12")))
    #expect(store.yearSummaryIsCurrent(2026) == false)
    #expect(store.writeYearSummary(2026) && store.yearSummaryIsCurrent(2026) == true)
    let text = store.read(path)
    #expect(text.contains("Año de mudanza.") && text.contains("### Para 2027\n- gastar menos fuera"))
    #expect(Edit.yearNoteComments(text) == "Año de mudanza.\n\n### Para 2027\n- gastar menos fuera")
}

@Test func fourthReviewOfExpenses() throws {
    let today = try #require(DayKey.date("2026-10-23"))
    let cats = testBudgetLines.map(\.0)
    // «abono» es el abono de transporte, no una devolución.
    let a = try #require(ExpenseParser.parse("abono transporte 20", categories: cats, today: today))
    #expect(a.amount == 20 && a.category == "Transporte")
    #expect(QuickCommand.parse("abono 20", today: today, categories: cats) == nil)

    // Un fijo pagado con un cargo y su devolución que se anulan cuenta 0, no lo previsto.
    var b = Parse.budget(octubre, month: "2026-10", path: "x")
    b.moves += [BudgetMove(date: today, amount: 850, category: "Vivienda", note: "", line: 900),
                BudgetMove(date: today, amount: -850, category: "Vivienda", note: "devolución", line: 901)]
    #expect(b.real(try #require(b.line(named: "Vivienda"))) == 0)

    // Corregir el importe de un movimiento en una tabla escrita a mano sin columna «Nota».
    let short = "## Movimientos\n| Fecha | Importe | Partida |\n| :--- | ---: | :--- |\n| 2026-10-02 | 120 | Comida |\n"
    let m = try #require(Parse.budget(short, month: "2026-10", path: "x").moves.first)
    let fixed = try #require(Edit.updateBudgetMove(short, month: "2026-10", move: m, date: m.date, amount: 112.4, note: ""))
    #expect(Parse.budget(fixed, month: "2026-10", path: "x").moves.first?.amount == 112.4)
}

@Test func monthsNotStartedShowWhatIsPlanned() throws {
    // Como la nota real: noviembre creado en octubre, con dos fijos ya marcados y la comunidad de cada 3 meses que no toca.
    let nov = """
    ## Ingresos
    | Concepto | Previsto | Real |
    | :--- | ---: | ---: |
    | Nómina | 1957 | 1957 |
    | Ingresos adicionales | 1200 | 1200 |

    ## Partidas
    | Partida | Previsto | Tipo | Pagado | Día | Cada | Desde |
    | :--- | ---: | :--- | :---: | ---: | :---: | :--- |
    | Vivienda | 525 | Fijo | ✅ |  |  |  |
    | Alimentación | 0 | Variable |  |  |  |  |
    | Ordenador | 70 | Fijo | ✅ |  |  |  |
    | Seguro vida | 37 | Fijo |  |  |  |  |
    | Gastos comunidad | 500 | Variable |  |  | 3 | 2027-01 |
    | Ahorro | 100 | Ahorro |  |  |  |  |
    """
    let y = BudgetYear(year: 2026, budgets: [Parse.budget(nov, month: "2026-11", path: "x")], today: try #require(DayKey.date("2026-10-23")))
    let m = try #require(y.months.first)
    #expect(m.planned && y.future == ["2026-11"] && y.current == nil && y.averageSpent == nil)
    #expect(m.income == 3157 && m.spent == 525 + 70 + 37 && m.left == 3157 - 632)
    #expect(Edit.budgetYearNote(y).contains("(previsto)"))
}

@MainActor @Test func paidContributionIsAnExpenseAndUndoesInOneStep() throws {
    let store = try undoVault()
    let path = "Finanzas/Boda Luis y Jazmin.md"
    try "---\ntipo: evento\nestado: pendiente\naportacion_eur: 150\n---\n# Boda\n".write(to: store.url(path).creatingParent(), atomically: true, encoding: .utf8)
    store.reload()
    #expect(store.pendingContributions.map(\.amount) == [150])
    let day = try #require(DayKey.date("2026-12-05"))
    store.payContribution(path: path, amount: 150, date: day)
    let m = try #require(store.budget("2026-12")?.moves.first)
    #expect(m.amount == 150 && m.category == "Imprevistos / otros" && m.note == "aportación [[Boda Luis y Jazmin]]")
    #expect(store.noteMeta[path]?["estado"] == "pagado" && store.pendingContributions.isEmpty)
    // Un solo deshacer quita el gasto, la nota del mes creada para él y el «pagado».
    store.undo()
    #expect(store.message == nil && store.budget("2026-12") == nil && store.noteMeta[path]?["estado"] == "pendiente")
}

@MainActor @Test func incomesCanBeAddedAndRemovedAndSummaryIsExported() throws {
    let store = try undoVault()
    store.addExpense(40, category: "Transporte", note: "", date: try #require(DayKey.date("2026-09-03")))
    var b = try #require(store.budget("2026-09"))
    store.addBudgetIncome(b, name: "Paga extra")
    b = try #require(store.budget("2026-09"))
    let extra = try #require(b.incomes.first { $0.name == "Paga extra" })
    store.setBudgetCell(b, section: "Ingresos", line: extra.line, name: extra.name, column: "Real", value: "900")
    #expect(store.budget("2026-09")?.income == 900)
    store.addBudgetIncome(try #require(store.budget("2026-09")), name: "paga extra")
    #expect(store.budget("2026-09")?.incomes.count == 3 && store.message?.contains("Ya hay") == true)
    store.removeBudgetIncome(try #require(store.budget("2026-09")), try #require(store.budget("2026-09")?.incomes.first { $0.name == "Nómina" }))
    #expect(store.budget("2026-09")?.incomes.map(\.name) == ["Ingresos adicionales", "Paga extra"])

    let out = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
    let files = try store.exportData(to: out)
    let csv = try String(contentsOf: try #require(files.first { $0.lastPathComponent == "resumen_mensual.csv" }), encoding: .utf8)
    #expect(csv == "mes,ingresos_eur,gastos_eur,queda_eur,previsto\n2026-09,900,40,860,0\n")
    let cats = try String(contentsOf: try #require(files.first { $0.lastPathComponent == "resumen_partidas.csv" }), encoding: .utf8)
    #expect(cats.hasPrefix("año,partida,tipo,previsto_eur,gastado_eur\n2026,Transporte,Variable,") && cats.contains(",40\n"))
}

@MainActor @Test func yearSummaryAddsUpCategoriesSavingsAndComparesWithLastYear() throws {
    let store = try undoVault()
    // 2025: marzo y abril; 2026: marzo, abril y mayo (este, en curso, no se compara).
    for (date, amount) in [("2025-03-10", 200.0), ("2025-04-10", 200), ("2026-03-10", 250), ("2026-04-10", 250), ("2026-05-02", 999)] {
        store.addExpense(amount, category: "Alimentación", note: "", date: try #require(DayKey.date(date)))
    }
    store.addExpense(30, category: "Transporte", note: "", date: try #require(DayKey.date("2026-03-12")))
    let mar = try #require(store.budget("2026-03"))
    let ahorro = try #require(mar.lines.first { $0.kind == .ahorro })
    store.addExpense(100, category: ahorro.name, note: "", date: try #require(DayKey.date("2026-03-15")))
    // Una partida que no está en la tabla cuenta igual, con su nombre.
    store.edit(mar.path) { $0 + "| 2026-03-20 | 15 | Regalos | cumple |\n" }

    let today = try #require(DayKey.date("2026-05-20"))
    let all = store.budgetMonths.compactMap { store.budget($0) }
    let y = BudgetYear(year: 2026, budgets: all, today: today), before = BudgetYear(year: 2025, budgets: all, today: today)
    let food = try #require(y.categories.first { $0.name == "Alimentación" })
    #expect(food.spent == 250 + 250 + 999 && food.kind == .variable)
    #expect(y.categories.first { $0.name == "Regalos" }.map { $0.kind == nil && $0.spent == 15 } == true)
    // Las partidas suman lo mismo que los meses, y el ahorro va aparte.
    #expect(abs(y.expenseCategories.reduce(0) { $0 + $1.spent } - y.spent) < 0.001)
    #expect(y.saved == 100 && y.months.first?.saved == 100 && !y.expenseCategories.contains { $0.kind == .ahorro })
    #expect(y.categories.map(\.spent) == y.categories.map(\.spent).sorted(by: >))

    // Marzo y abril frente a los de 2025; mayo, en curso, se queda fuera.
    let c = try #require(y.spentChange(from: before))
    #expect(c.months == [3, 4] && c.now == 250 + 30 + 15 + 250 && c.before == 400)
    #expect(y.spentChange(from: BudgetYear(year: 2024, budgets: all, today: today)) == nil)

    let note = Edit.budgetYearNote(y, today: today)
    #expect(note.contains("## Por partida") && note.contains("| Regalos | Sin partida | – | \(Money.format(15)) | – |"))
    #expect(note.contains("Apartado en partidas de ahorro: \(Money.format(100))"))
    // Los comentarios siguen al final, después de las partidas.
    #expect(Edit.yearNoteComments(Edit.budgetYearNote(y, comments: "Ojo con la comida.")) == "Ojo con la comida.")
}

@Test func moneyShowsSignedDifferencesAndPercentages() {
    #expect(Money.signed(120) == "+" + Money.format(120) && Money.signed(-80.4) == "−" + Money.format(80) && Money.signed(0.3) == Money.format(0))
    #expect(Money.percent(0.284) == "28 %" && Money.percent(-0.1) == "-10 %")
}

@Test func foldedSearchAndMoveKeysStayInSync() throws {
    #expect(MD.contains(MD.fold("Cita con el Médico 📅 2026"), "medico") && MD.contains("abc", "") && !MD.contains("abc", "abd"))
    var m = BudgetMove(date: try #require(DayKey.date("2026-10-01")), amount: 5, category: "Alimentación", note: "", line: 1)
    #expect(m.key == "alimentacion")
    m.category = "Ocio"
    #expect(m.key == "ocio")
}

@Test func defaultLinesKeepGymAndPhoneApart() {
    let cats = Edit.defaultBudgetLines.map(\.0)
    let today = DayKey.date("2026-10-20")!
    #expect(ExpenseParser.parse("O2 35", categories: cats, today: today)?.category == "Internet y móvil")
    #expect(ExpenseParser.parse("gimnasio 40", categories: cats, today: today)?.category == "Salud y deporte")
    #expect(ExpenseParser.parse("dentista 60", categories: cats, today: today)?.category == "Salud y deporte")
    // con una partida que lleva «O2» en el nombre, va a esa
    #expect(ExpenseParser.parse("o2 40", categories: testBudgetLines.map(\.0), today: today)?.category == "Gym + O2")
}

@Test func aMonthWithNothingLoggedSaysSo() throws {
    let text = Edit.budgetNote(month: "2026-10", from: nil, defaults: testBudgetLines).replacingOccurrences(of: "| Alimentación | 0 |", with: "| Alimentación | 350 |")
    let b = Parse.budget(text, month: "2026-10", path: "x")
    let early = BudgetStatus(b, today: DayKey.date("2026-10-04")!)
    let late = BudgetStatus(b, today: DayKey.date("2026-10-23")!)
    #expect(!b.nothingLogged(early) && b.nothingLogged(late))
    #expect(Budget.insights(b, previous: [], status: late).first?.id == "sin-apuntar")
    let moved = try #require(Edit.addBudgetMove(text, date: DayKey.date("2026-10-05")!, amount: 20, category: "Alimentación", note: ""))
    let logged = Parse.budget(moved, month: "2026-10", path: "x")
    #expect(!logged.nothingLogged(BudgetStatus(logged, today: DayKey.date("2026-10-23")!)))
}
