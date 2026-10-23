import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Gráficas dentro de una nota

private let sleepNote = """
# Diario

## Sueño
| Fecha | Horas | Ánimo | Nota |
|---|---|---|---|
| 02/10/2026 | 6 | 3 | mal |
| 01/10/2026 | 7,5 h | 4 | bien |
| 03/10/2026 |  | 5 | |

## Gastos
| Categoría | Importe |
|---|---|
| Comida | 12,50 € |
| Ocio | 30 € |
| Comida | 7,50 € |

```grafica
tabla: Sueño
```
"""

@Test func chartBlockIsParsed() {
    let blocks = MDParser.blocks("Texto\n\n```Gráfica\ntipo: Barras\ny: Horas, Ánimo\n```\n\n```swift\nlet a = 1\n```\n")
    guard case .chart(let body) = blocks[1] else { Issue.record("no es gráfica"); return }
    let s = NoteChart.spec(body)
    #expect(s.kind == .barras && s.y == ["Horas", "Ánimo"] && s.table == nil && s.x == nil)
    if case .code = blocks[2] {} else { Issue.record("el código normal sigue siendo código") }
    #expect(NoteChart.spec("tipo: quesito\nTítulo: Gastos\nsección: Gastos").kind == .tarta)
    #expect(NoteChart.spec("tipo: inventado").kind == .linea)   // un tipo que no existe deja el de siempre
}

@Test func chartDataByDateWithDefaults() throws {
    let tables = Parse.tables(sleepNote)
    let d = try NoteChart.data(NoteChart.spec("tabla: sueño"), tables: tables).get()
    // x es la primera columna; y, las columnas con números (no «Nota»); las fechas se ordenan
    #expect(d.byDate && d.xTitle == "Fecha" && d.series == ["Horas", "Ánimo"])
    #expect(d.points.map(\.label) == ["01/10/2026", "01/10/2026", "02/10/2026", "02/10/2026", "03/10/2026"])
    #expect(d.points.filter { $0.series == "Horas" }.map(\.value) == [7.5, 6])   // la celda vacía no es un 0
    #expect(d.points.map(\.id) == Array(0..<5))
    #expect(d.units.isEmpty)   // «7,5 h» y «6» no llevan la misma unidad
}

@Test func chartDataSumsCategoriesForBarsAndPie() throws {
    let tables = Parse.tables(sleepNote)
    let bars = try NoteChart.data(NoteChart.spec("tabla: Gastos\ntipo: barras"), tables: tables).get()
    #expect(!bars.byDate && bars.points.map(\.label) == ["Comida", "Ocio"] && bars.points.map(\.value) == [20, 30])
    #expect(bars.units == ["Importe": "€"] && bars.format(20, "Importe") == "20 €" && bars.format(1234.5, "Importe") == "1234,5 €")
    let line = try NoteChart.data(NoteChart.spec("tabla: Gastos"), tables: tables).get()
    #expect(line.points.count == 3)   // en una línea cada fila es un punto
    let pie = try NoteChart.data(NoteChart.spec("tabla: Gastos\ntipo: tarta"), tables: tables).get()
    #expect(pie.points.map(\.label) == ["Ocio", "Comida"])   // de mayor a menor
}

@Test func chartPieGroupsSmallSlicesAndKeepsOneSeries() throws {
    let rows = (1...10).map { "| C\($0) | \($0) | \($0 * 2) |" }.joined(separator: "\n")
    let tables = Parse.tables("| Cosa | A | B |\n|---|---|---|\n\(rows)\n")
    let pie = try NoteChart.data(NoteChart.spec("tipo: tarta"), tables: tables).get()
    #expect(pie.series == ["A"] && pie.omitted == ["B"])
    #expect(pie.points.count == NoteChart.maxSlices && pie.points.last?.label == "Otros")
    #expect(pie.points.last?.value == Double((1...4).reduce(0, +)))
    #expect(pie.points.reduce(0) { $0 + $1.value } == 55)
}

@Test func chartProblemsAreExplained() {
    func problem(_ spec: String, _ text: String = sleepNote) -> String? {
        if case .failure(let p) = NoteChart.data(NoteChart.spec(spec), tables: Parse.tables(text)) { return p.message }
        return nil
    }
    #expect(problem("", "Solo texto") == "La nota no tiene ninguna tabla que dibujar.")
    #expect(problem("tabla: Peso")?.hasPrefix("No encuentro la tabla «Peso»") == true)
    #expect(problem("tabla: Sueño\ny: Pasos") == "No encuentro la columna «Pasos».")
    #expect(problem("tabla: Sueño\nx: Hora") == nil)   // «Hora» encuentra «Horas»
    #expect(problem("", "| A | B |\n|---|---|\n| x | y |\n")?.hasPrefix("No hay columnas con números") == true)
    #expect(problem("y: B", "| A | B |\n|---|---|\n| x | y |\n") == "No hay números en «B».")
}

@Test func chartNumericCells() {
    #expect(NoteChart.isNumeric("12,50 €") && NoteChart.isNumeric("7,5 h") && NoteChart.isNumeric("-3") && NoteChart.isNumeric("1.234,5"))
    #expect(!NoteChart.isNumeric("01/10/2026") && !NoteChart.isNumeric("2026-10-01") && !NoteChart.isNumeric("Semana 3") && !NoteChart.isNumeric("bien"))
}

@MainActor @Test func chartViewsRender() throws {
    let tables = Parse.tables(sleepNote)
    for spec in ["tabla: Sueño", "tabla: Sueño\ntipo: barras", "tabla: Sueño\ntipo: area", "tabla: Sueño\ntipo: puntos",
                 "tabla: Gastos\ntipo: tarta\ntitulo: Gastos", "tabla: Gastos\ntipo: barras", "tabla: Nada"] {
        let r = ImageRenderer(content: NoteChartView(spec: NoteChart.spec(spec), tables: tables).frame(width: 700))
        #expect(r.cgImage != nil, "\(spec)")
    }
}
