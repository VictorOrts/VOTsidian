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
    #expect(first.lines.count == 14 && first.lines.contains { $0.kind == .ahorro })

    let added = try #require(Edit.addBudgetMove(text, date: DayKey.date("2026-11-03")!, amount: 22.5, category: "Alimentación", note: "pan"))
    let after = Parse.budget(added, month: "2026-11", path: "y")
    #expect(after.moves.count == 1 && after.moves[0].amount == 22.5)
    #expect(added.contains("| 2026-11-03 | 22,50 | Alimentación | pan |"))
    #expect(added.hasSuffix("[[Finanzas]]\n"))
}

@Test func expensePhrasesAreUnderstood() throws {
    let cats = Edit.defaultBudgetLines.map(\.0)
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
    #expect(b.moves.count == 1 && b.lines.count == 14)
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
    let seguro = try #require(b.line(named: "Seguro vida"))
    store.setBudgetFrequency(b, seguro, every: 3, start: "2026-11")
    let after = try #require(store.budget("2026-09")?.line(named: "Seguro vida"))
    #expect(after.every == 3 && after.start == "2026-11" && after.planned == 0)
    #expect(store.budget("2026-09")?.lines.count == 14 && store.budget("2026-09")?.moves.count == 1)

    // Una fila escrita a mano con menos celdas también se puede marcar como pagada.
    store.edit(path) { $0.replacingOccurrences(of: #"\| Ordenador \|[^\n]*"#, with: "| Ordenador | 60 | Fijo |", options: .regularExpression) }
    let short = try #require(store.budget("2026-09")?.line(named: "Ordenador"))
    store.setBudgetCell(try #require(store.budget("2026-09")), section: "Partidas", line: short.line, name: short.name, column: "Pagado", value: "✅")
    #expect(store.budget("2026-09")?.line(named: "Ordenador")?.paid == true)
}

@MainActor @Test func linesCanBeAddedRenamedAndRemoved() throws {
    let store = try undoVault()
    store.addExpense(30, category: "Vivienda (alquiler, hipoteca, impuestos, seguro)", note: "", date: try #require(DayKey.date("2026-11-03")))
    var b = try #require(store.budget("2026-11"))
    store.addBudgetLine(b, name: "Seguro vivienda", amount: 0, kind: .fijo, every: 12, start: "2027-03")
    b = try #require(store.budget("2026-11"))
    let seguro = try #require(b.line(named: "Seguro vivienda"))
    #expect(seguro.every == 12 && seguro.start == "2027-03" && !seguro.isDue("2026-11") && seguro.isDue("2027-03") && seguro.isDue("2028-03"))
    store.addBudgetLine(b, name: "seguro vivienda", amount: 0, kind: .fijo, every: 1, start: nil)
    #expect(store.budget("2026-11")?.lines.count == 15 && store.message?.contains("Ya hay") == true)

    let viv = try #require(b.line(named: "Vivienda (alquiler, hipoteca, impuestos, seguro)"))
    store.renameBudgetLine(b, viv, to: "Vivienda (alquiler, hipoteca, impuestos)")
    b = try #require(store.budget("2026-11"))
    let renamed = try #require(b.line(named: "Vivienda (alquiler, hipoteca, impuestos)"))
    #expect(b.real(renamed) == 30 && b.unassigned == 0)

    store.removeBudgetLine(b, try #require(b.line(named: "Ordenador")))
    #expect(store.budget("2026-11")?.line(named: "Ordenador") == nil && store.budget("2026-11")?.lines.count == 14)
}

@Test func reviewFixesForExpenses() throws {
    let today = try #require(DayKey.date("2026-10-23"))
    let cats = Edit.defaultBudgetLines.map(\.0) + ["Seguro vivienda"]
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
    let cats = Edit.defaultBudgetLines.map(\.0)
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
