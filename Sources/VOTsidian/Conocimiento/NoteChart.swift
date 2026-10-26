import Charts
import SwiftUI

// MARK: - Gráficas dentro de una nota
//
// Un bloque de código `grafica` dibuja una tabla de la misma nota:
//
//     ```grafica
//     tabla: Sueño          (título de la sección de la tabla; sin él, la primera tabla)
//     x: Fecha              (sin él, la primera columna)
//     y: Horas, Despertares  (sin él, todas las columnas con números)
//     tipo: linea           (linea, barras, area, puntos o tarta)
//     titulo: Cómo duermo
//     ```
//
// En Obsidian se sigue viendo como código; no rompe nada.

struct ChartSpec: Equatable {
    enum Kind: String, CaseIterable { case linea, barras, area, puntos, tarta }
    var kind = Kind.linea
    var title: String?
    var table: String?
    var x: String?
    var y: [String] = []
}

struct ChartPoint: Identifiable, Equatable {
    var id: Int
    /// Texto de la columna x tal cual (para categorías y para el detalle al pasar el ratón).
    var label: String
    /// Si toda la columna x son fechas, el eje es de tiempo.
    var date: Date?
    var series: String
    var value: Double
}

struct ChartData: Equatable {
    var points: [ChartPoint]
    var series: [String]
    var xTitle: String
    var byDate: Bool
    /// Columnas con números que no se dibujan porque ya hay demasiadas series.
    var omitted: [String] = []
    /// Unidad de cada serie («€», «h», «kg»…), si todas sus celdas la llevan.
    var units: [String: String] = [:]

    func format(_ value: Double, _ series: String) -> String {
        NoteChart.number(value) + (units[series].map { " \($0)" } ?? "")
    }
}

enum NoteChart {
    /// Más series no se distinguen por color: el resto se nombra debajo de la gráfica.
    static let maxSeries = 8
    /// En una tarta, a partir de aquí las porciones pequeñas se juntan en «Otros».
    static let maxSlices = 7

    /// Lenguajes de bloque que se dibujan como gráfica.
    static func isChartBlock(_ lang: Substring) -> Bool {
        ["grafica", "grafico", "chart"].contains(MD.fold(String(lang)))
    }

    /// Lee las líneas «clave: valor» del bloque. Las claves y los tipos aceptan tildes, mayúsculas y algún sinónimo.
    static func spec(_ body: String) -> ChartSpec {
        var s = ChartSpec()
        for line in MD.lines(body) {
            guard let c = line.firstIndex(of: ":") else { continue }
            let key = MD.fold(String(line[..<c]))
            let value = String(line[line.index(after: c)...]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            switch key {
            case "tipo", "type": s.kind = kind(value) ?? s.kind
            case "titulo", "title": s.title = value
            case "tabla", "table", "seccion": s.table = value
            case "x": s.x = value
            case "y": s.y = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            default: continue
            }
        }
        return s
    }

    static func kind(_ text: String) -> ChartSpec.Kind? {
        switch MD.fold(text) {
        case "linea", "lineas", "line": .linea
        case "barras", "barra", "bar", "bars", "columnas": .barras
        case "area", "areas": .area
        case "puntos", "punto", "dispersion", "points", "scatter": .puntos
        case "tarta", "quesito", "circular", "pie", "donut", "rosco": .tarta
        default: nil
        }
    }

    static func date(_ cell: String) -> Date? { DayKey.date(cell) ?? DayKey.dmyDate(cell) }

    /// Ancho de las barras en un eje de fechas: el del espacio típico entre fechas (un registro al mes → barras de un
    /// mes). Con barras de un día, unos datos mensuales salían como rayas.
    static func barUnit(_ dates: [Date]) -> Calendar.Component {
        let days = Set(dates).sorted()
        let gaps = zip(days, days.dropFirst()).map { DayKey.days(from: $0, to: $1) }.sorted()
        guard !gaps.isEmpty else { return .day }
        let typical = gaps[gaps.count / 2]
        return typical >= 28 ? .month : typical >= 7 ? .weekOfYear : .day
    }

    static func number(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "es_ES")))
    }

    /// Lo que va detrás del número («12,50 €» → «€»), o `nil` si las celdas no coinciden o no llevan nada.
    static func unit(_ cells: [String]) -> String? {
        let suffixes = Set(cells.filter { MD.number($0) != nil }.map { c in
            String(c[(c.lastIndex(where: \.isNumber).map(c.index(after:)) ?? c.endIndex)...]).trimmingCharacters(in: .whitespaces)
        })
        guard suffixes.count == 1, let u = suffixes.first, !u.isEmpty, u.count <= 4 else { return nil }
        return u
    }

    /// Celda que es un número (con «€», «kg», «%»… detrás), no una fecha ni un texto con un número dentro.
    static func isNumeric(_ cell: String) -> Bool {
        let t = cell.trimmingCharacters(in: .whitespaces)
        guard MD.number(t) != nil, date(t) == nil else { return false }
        return t.filter { !$0.isNumber && !",.-+ ".contains($0) }.count <= 3
    }

    /// Los puntos que hay que dibujar, o por qué no se puede.
    static func data(_ spec: ChartSpec, tables: [NamedTable]) -> Result<ChartData, ChartProblem> {
        guard !tables.isEmpty else { return .failure("La nota no tiene ninguna tabla que dibujar.") }
        let table: NamedTable
        if let name = spec.table {
            let key = MD.fold(name)
            guard let t = tables.first(where: { MD.fold($0.title) == key }) ?? tables.first(where: { MD.fold($0.title).contains(key) }) else {
                return .failure("No encuentro la tabla «\(name)». Pon el título de la sección donde está.")
            }
            table = t
        } else { table = tables[0] }
        guard !table.rows.isEmpty else { return .failure("La tabla no tiene filas.") }

        func col(_ name: String) -> Int? {
            let key = MD.fold(name)
            return table.header.firstIndex { MD.fold($0) == key } ?? table.header.firstIndex { MD.fold($0).contains(key) }
        }
        func cell(_ r: TableRow, _ i: Int) -> String { i < r.cells.count ? r.cells[i].trimmingCharacters(in: .whitespaces) : "" }

        let xi: Int
        if let x = spec.x {
            guard let i = col(x) else { return .failure("No encuentro la columna «\(x)».") }
            xi = i
        } else { xi = 0 }

        var ys: [Int] = []
        if spec.y.isEmpty {
            ys = table.header.indices.filter { i in
                guard i != xi else { return false }
                let filled = table.rows.map { cell($0, i) }.filter { !$0.isEmpty }
                return !filled.isEmpty && filled.filter(isNumeric).count * 2 >= filled.count
            }
        } else {
            for name in spec.y {
                guard let i = col(name) else { return .failure("No encuentro la columna «\(name)».") }
                if !ys.contains(i) { ys.append(i) }
            }
        }
        guard !ys.isEmpty else { return .failure("No hay columnas con números que dibujar. Indica cuáles con «y: Columna».") }
        let limit = spec.kind == .tarta ? 1 : maxSeries
        let omitted = ys.dropFirst(limit).map { table.header[$0] }
        ys = Array(ys.prefix(limit))

        let xs = table.rows.map { cell($0, xi) }.filter { !$0.isEmpty }
        let byDate = !xs.isEmpty && xs.allSatisfy { date($0) != nil }
        var points: [ChartPoint] = []
        for r in table.rows {
            let x = cell(r, xi)
            guard !x.isEmpty else { continue }
            for i in ys {
                guard let v = MD.number(cell(r, i)) else { continue }
                points.append(ChartPoint(id: points.count, label: x, date: byDate ? date(x) : nil, series: table.header[i], value: v))
            }
        }
        // Barras y tartas por categoría: la misma categoría en varias filas (gastos de «Comida») se suma.
        if !byDate, spec.kind == .barras || spec.kind == .tarta {
            var merged: [ChartPoint] = []
            var at: [String: Int] = [:]
            for p in points {
                let key = p.series + "\u{0}" + p.label
                if let i = at[key] { merged[i].value += p.value } else { at[key] = merged.count; merged.append(p) }
            }
            points = merged
        }
        if spec.kind == .tarta {
            points = points.filter { $0.value > 0 }.sorted { $0.value > $1.value }
            if points.count > maxSlices {
                let rest = points[(maxSlices - 1)...].reduce(0) { $0 + $1.value }
                points = Array(points.prefix(maxSlices - 1)) + [ChartPoint(id: -1, label: "Otros", series: points[0].series, value: rest)]
            }
        }
        if byDate { points.sort { ($0.date ?? .distantPast, $0.id) < ($1.date ?? .distantPast, $1.id) } }
        for i in points.indices { points[i].id = i }
        guard !points.isEmpty else {
            return .failure("Todavía no hay números en \(ys.map { "«\(table.header[$0])»" }.joined(separator: ", ")): la gráfica sale al rellenar la tabla.")
        }
        var units: [String: String] = [:]
        for i in ys { units[table.header[i]] = unit(table.rows.map { cell($0, i) }) }
        return .success(ChartData(points: points, series: ys.map { table.header[$0] }, xTitle: table.header.indices.contains(xi) ? table.header[xi] : "",
                                  byDate: byDate, omitted: omitted, units: units))
    }
}

struct ChartProblem: Error, Equatable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    var message: String
    init(stringLiteral value: String) { message = value }
    init(stringInterpolation: DefaultStringInterpolation) { message = String(stringInterpolation: stringInterpolation) }
}

// MARK: - Vista

struct NoteChartView: View {
    let spec: ChartSpec
    let tables: [NamedTable]
    @State private var hoverDate: Date?
    @State private var hoverLabel: String?
    @State private var hoverAngle: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let t = spec.title { Text(t).font(.headline) }
            switch NoteChart.data(spec, tables: tables) {
            case .failure(let p):
                Label(p.message, systemImage: "chart.xyaxis.line").font(.callout).foregroundStyle(Brand.warn)
            case .success(let d):
                if spec.kind == .tarta { pie(d) } else { plot(d) }
                if !d.omitted.isEmpty {
                    Text("Sin dibujar (demasiadas series): \(d.omitted.joined(separator: ", ")). Elige cuáles con «y:».").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: Brand.radius))
    }

    /// El color va con la serie, en el orden de la paleta de la app: una serie nueva no repinta las demás.
    private func colors(_ names: [String]) -> [Color] { names.indices.map { Brand.series[$0 % Brand.series.count] } }

    // MARK: Línea, área, barras y puntos

    private func plot(_ d: ChartData) -> some View {
        let single = d.series.count == 1
        return Chart {
            ForEach(d.points) { p in
                mark(p, d)
                    .foregroundStyle(by: .value("Serie", p.series))
            }
            if let p = selectedX(d) {
                if let date = p.date { RuleMark(x: .value(d.xTitle, date)).foregroundStyle(Color.secondary.opacity(0.4)) }
                else { RuleMark(x: .value(d.xTitle, p.label)).foregroundStyle(Color.secondary.opacity(0.4)) }
            }
        }
        .chartForegroundStyleScale(domain: d.series, range: colors(d.series))
        .chartLegend(single ? .hidden : .visible)
        .chartLegend(position: .top, alignment: .leading)
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel { if let n = v.as(Double.self) { Text(NoteChart.number(n)) } }
            }
        }
        // «Importe (€)», pero no «Aportado (€) (€)» si la columna ya dice la unidad.
        .chartYAxisLabel(single ? d.series[0] + (d.units[d.series[0]].flatMap { d.series[0].contains($0) ? nil : " (\($0))" } ?? "") : "")
        .modifier(XSelection(byDate: d.byDate, date: $hoverDate, label: $hoverLabel))
        .overlay(alignment: .topTrailing) { if let p = selectedX(d) { tooltip(for: p, d) } }
        .frame(height: 240)
    }

    @ChartContentBuilder private func mark(_ p: ChartPoint, _ d: ChartData) -> some ChartContent {
        let y = PlottableValue.value("Valor", p.value)
        if let date = p.date {
            let x = PlottableValue.value(d.xTitle, date)
            switch spec.kind {
            case .barras: BarMark(x: .value(d.xTitle, date, unit: NoteChart.barUnit(d.points.compactMap(\.date))), y: y).position(by: .value("Serie", p.series)).cornerRadius(3)
            case .area: AreaMark(x: x, y: y, stacking: .unstacked).opacity(0.25).interpolationMethod(.monotone)
                LineMark(x: x, y: y, series: .value("Serie", p.series)).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.monotone)
            case .puntos: PointMark(x: x, y: y).symbolSize(50)
            case .linea, .tarta: LineMark(x: x, y: y, series: .value("Serie", p.series)).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.monotone)
                .symbol(.circle).symbolSize(d.points.count > 60 ? 0 : 24)
            }
        } else {
            let x = PlottableValue.value(d.xTitle, p.label)
            switch spec.kind {
            case .barras: BarMark(x: x, y: y).position(by: .value("Serie", p.series)).cornerRadius(3)
            case .area: AreaMark(x: x, y: y, stacking: .unstacked).opacity(0.25)
                LineMark(x: x, y: y, series: .value("Serie", p.series)).lineStyle(StrokeStyle(lineWidth: 2))
            case .puntos: PointMark(x: x, y: y).symbolSize(50)
            case .linea, .tarta: LineMark(x: x, y: y, series: .value("Serie", p.series)).lineStyle(StrokeStyle(lineWidth: 2))
                .symbol(.circle).symbolSize(24)
            }
        }
    }

    /// Primer punto de la x que está bajo el ratón (la fecha más cercana, o la categoría).
    private func selectedX(_ d: ChartData) -> ChartPoint? {
        if d.byDate, let h = hoverDate {
            return d.points.min { abs($0.date!.timeIntervalSince(h)) < abs($1.date!.timeIntervalSince(h)) }
        }
        if !d.byDate, let h = hoverLabel { return d.points.first { $0.label == h } }
        return nil
    }

    private func tooltip(for p: ChartPoint, _ d: ChartData) -> some View {
        let same = d.points.filter { $0.label == p.label }
        let palette = colors(d.series)
        return VStack(alignment: .leading, spacing: 3) {
            Text(p.date.map { DayKey.dmy($0) } ?? p.label).font(.caption.weight(.semibold))
            ForEach(same) { q in
                HStack(spacing: 6) {
                    if d.series.count > 1 { Circle().fill(palette[d.series.firstIndex(of: q.series) ?? 0]).frame(width: 7, height: 7) }
                    Text(q.series).foregroundStyle(.secondary)
                    Spacer(minLength: 10)
                    Text(d.format(q.value, q.series)).monospacedDigit()
                }.font(.caption)
            }
        }
        .padding(8).frame(minWidth: 140)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Brand.radius))
        .allowsHitTesting(false)
    }

    // MARK: Tarta

    private func pie(_ d: ChartData) -> some View {
        let total = d.points.reduce(0) { $0 + $1.value }
        let labels = d.points.map(\.label)
        let palette = colors(labels)
        let hovered = selectedSlice(d)
        return HStack(alignment: .center, spacing: 24) {
            Chart(d.points) { p in
                SectorMark(angle: .value(d.series[0], p.value), innerRadius: .ratio(0.55), angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(by: .value(d.xTitle, p.label))
                    .opacity(hovered == nil || hovered?.id == p.id ? 1 : 0.4)
            }
            .chartForegroundStyleScale(domain: labels, range: palette)
            .chartLegend(.hidden)
            .chartAngleSelection(value: $hoverAngle)
            .chartBackground { _ in
                VStack(spacing: 2) {
                    Text(hovered?.label ?? "Total").font(.caption).foregroundStyle(.secondary)
                    Text(d.format(hovered?.value ?? total, d.series[0])).font(.title3.weight(.semibold)).monospacedDigit()
                    if let h = hovered, total > 0 { Text(percentText(h.value / total)).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .frame(width: 220, height: 220)
            // La leyenda hace de tabla: nombre, valor y porcentaje, así el color nunca es lo único que identifica.
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                ForEach(d.points) { p in
                    GridRow {
                        RoundedRectangle(cornerRadius: 2).fill(palette[p.id % palette.count]).frame(width: 10, height: 10)
                        Text(p.label).lineLimit(1)
                        Text(d.format(p.value, p.series)).monospacedDigit().gridColumnAlignment(.trailing)
                        Text(total > 0 ? percentText(p.value / total) : "").foregroundStyle(.secondary).monospacedDigit().gridColumnAlignment(.trailing)
                    }
                    .font(.callout)
                    .fontWeight(hovered?.id == p.id ? .semibold : .regular)
                }
            }
        }
    }

    /// Porción bajo el ratón: el ángulo seleccionado es el acumulado de los valores.
    private func selectedSlice(_ d: ChartData) -> ChartPoint? {
        guard let a = hoverAngle else { return nil }
        var acc = 0.0
        for p in d.points { acc += p.value; if a <= acc { return p } }
        return nil
    }
}

/// Selección por fecha o por categoría, según el eje x.
private struct XSelection: ViewModifier {
    let byDate: Bool
    @Binding var date: Date?
    @Binding var label: String?

    func body(content: Content) -> some View {
        if byDate { content.chartXSelection(value: $date) } else { content.chartXSelection(value: $label) }
    }
}
