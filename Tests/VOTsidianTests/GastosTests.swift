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
