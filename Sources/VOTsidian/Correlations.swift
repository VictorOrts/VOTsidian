import Charts
import SwiftUI

/// Una semana (lunes a domingo) con lo que se midió en ella.
struct WeekPoint: Equatable {
    var start: Date
    var sleep: Double?
    var kgChange: Double?   // peso al final de la semana menos peso al final de la anterior
    var mg: Double?         // dosis vigente al final de la semana
}

struct CorrelationPair: Identifiable, Equatable {
    var title: String
    var r: Double?
    var n: Int
    var xs: [Double] = []
    var ys: [Double] = []
    var xLabel = ""
    var yLabel = ""
    var id: String { title }

    /// Color según la fuerza: verde si es clara, naranja si es débil, neutro si no hay relación.
    var tint: Color? {
        guard let r else { return nil }
        let a = abs(r)
        return a >= 0.4 ? Brand.accent : a >= 0.2 ? Brand.warn : nil
    }

    /// Recta de mínimos cuadrados para pintarla sobre los puntos.
    var fit: (slope: Double, intercept: Double)? {
        let n = Double(xs.count)
        guard n >= 2 else { return nil }
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        return (sxy / sxx, my - sxy / sxx * mx)
    }

    /// Frase corta y prudente: la correlación no prueba que una cosa cause la otra.
    var reading: String {
        guard let r else { return "Faltan datos (mínimo \(Correlations.minPoints) semanas con ambos valores)." }
        let a = abs(r)
        let strength = a < 0.2 ? "sin relación clara" : a < 0.4 ? "relación débil" : a < 0.6 ? "relación moderada" : "relación fuerte"
        if a < 0.2 { return strength }
        return strength + (r > 0 ? ": suben juntos" : ": cuando uno sube, el otro baja")
    }
}

enum Correlations {
    static let minPoints = 6

    static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= minPoints else { return nil }
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for (x, y) in zip(xs, ys) { sxy += (x - mx) * (y - my); sxx += (x - mx) * (x - mx); syy += (y - my) * (y - my) }
        guard sxx > 0, syy > 0 else { return nil }
        return sxy / (sxx * syy).squareRoot()
    }

    /// Semanas desde el primer pesaje hasta hoy. `sleep` devuelve la media entre dos fechas (ambas incluidas).
    static func weeks(weights: [WeightRecord], doses: [Dose], today: Date, sleep: (Date, Date) -> Double?) -> [WeekPoint] {
        let ws = weights.sorted { $0.date < $1.date }
        guard let first = ws.first else { return [] }
        func kg(upTo d: Date) -> Double? { ws.last { $0.date <= d }?.kg }
        func mg(upTo d: Date) -> Double? { doses.sorted { $0.date < $1.date }.last { $0.date <= d }?.mg }
        var out: [WeekPoint] = []
        var start = DayKey.weekStart(first.date)
        while start <= today {
            let end = DayKey.adding(days: 6, to: start)
            var change: Double?
            if let now = kg(upTo: end), let before = kg(upTo: DayKey.adding(days: -1, to: start)) { change = now - before }
            out.append(WeekPoint(start: start, sleep: sleep(start, end), kgChange: change, mg: mg(upTo: end)))
            start = DayKey.adding(days: 7, to: start)
        }
        return out
    }

    private static func pair(_ title: String, _ xLabel: String, _ yLabel: String, _ points: [WeekPoint], _ a: (WeekPoint) -> Double?, _ b: (WeekPoint) -> Double?) -> CorrelationPair {
        let both = points.compactMap { p -> (Double, Double)? in
            guard let x = a(p), let y = b(p) else { return nil }
            return (x, y)
        }
        return CorrelationPair(title: title, r: pearson(both.map(\.0), both.map(\.1)), n: both.count,
                               xs: both.map(\.0), ys: both.map(\.1), xLabel: xLabel, yLabel: yLabel)
    }

    static func pairs(_ points: [WeekPoint]) -> [CorrelationPair] {
        [pair("Dosis ↔ cambio de peso semanal", "Dosis (mg)", "Cambio (kg/sem)", points, \.mg, \.kgChange),
         pair("Sueño ↔ cambio de peso semanal", "Sueño (h)", "Cambio (kg/sem)", points, \.sleep, \.kgChange)]
    }
}

extension Store {
    func weekPoints(today: Date = DayKey.today()) -> [WeekPoint] {
        func avg(_ key: String) -> (Date, Date) -> Double? {
            { a, b in
                let v = self.diarySeries(key, from: a, to: b).map(\.1)
                return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
            }
        }
        return Correlations.weeks(weights: weight.records, doses: medicacion.doses, today: today, sleep: avg("sueno_h"))
    }
}

struct CorrelacionesView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let _ = BodyCounter.hit("CorrelacionesView")
        let points = store.weekPoints()
        let pairs = Correlations.pairs(points)
        let doses = store.medicacion.doses.sorted { $0.date < $1.date }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Aquí se cruzan peso, dosis y sueño por semanas. Una relación no prueba que una cosa cause la otra: sirve para sospechar y comentarlo con tu médico.")
                    .font(.callout).foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                    ForEach(pairs) { pairCard($0) }
                }

                Card(title: "Peso y dosis", icon: "scalemass") {
                    if store.weight.records.count < 2 { EmptyNote("Faltan registros de peso.", icon: "scalemass") }
                    else {
                        Chart {
                            ForEach(Array(doses.enumerated()), id: \.offset) { i, d in
                                let end = i + 1 < doses.count ? doses[i + 1].date : DayKey.today()
                                RectangleMark(xStart: .value("Desde", d.date), xEnd: .value("Hasta", end))
                                    .foregroundStyle((i % 2 == 0 ? Brand.accent : Brand.amber).opacity(0.10))
                                    .annotation(position: .top, alignment: .leading) { Text(d.dose).font(.caption2).foregroundStyle(.secondary) }
                            }
                            ForEach(store.weight.records) { r in
                                LineMark(x: .value("Fecha", r.date), y: .value("kg", r.kg))
                                PointMark(x: .value("Fecha", r.date), y: .value("kg", r.kg)).symbolSize(20)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 220)
                        .accessibilityLabel("Gráfica de peso con las dosis de \(store.medicacion.name) como bandas")
                    }
                }

                let withData = points.filter { $0.sleep != nil }
                if withData.isEmpty {
                    Card(title: "Sueño por semana", icon: "moon.zzz") { EmptyNote("Aún no hay sueño en las notas del día. Se anota con «dormí 7,5» en ⌘K.") }
                } else {
                    weeklyCard("Sueño por semana", icon: "moon.zzz", unit: "Sueño (h)", color: Brand.violet, domain: nil, data: withData.compactMap { p in p.sleep.map { (p.start, $0) } })
                }
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Correlaciones")
    }

    private func pairCard(_ p: CorrelationPair) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Tile(title: p.title, value: p.r.map { String(format: "%+.2f", $0).replacingOccurrences(of: ".", with: ",") } ?? "–",
                 note: p.reading + (p.r != nil ? " (\(p.n) semanas)" : ""), tint: p.tint)
            if p.r != nil {
                Chart {
                    ForEach(Array(zip(p.xs, p.ys).enumerated()), id: \.offset) { _, v in
                        PointMark(x: .value(p.xLabel, v.0), y: .value(p.yLabel, v.1))
                            .foregroundStyle((p.tint ?? Color.secondary).opacity(0.65)).symbolSize(45)
                    }
                    if let f = p.fit, let lo = p.xs.min(), let hi = p.xs.max() {
                        LineMark(x: .value(p.xLabel, lo), y: .value(p.yLabel, f.slope * lo + f.intercept), series: .value("s", "recta"))
                            .foregroundStyle(p.tint ?? Color.secondary).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        LineMark(x: .value(p.xLabel, hi), y: .value(p.yLabel, f.slope * hi + f.intercept), series: .value("s", "recta"))
                            .foregroundStyle(p.tint ?? Color.secondary).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }
                }
                .chartXScale(domain: .automatic(includesZero: false))
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxisLabel(p.xLabel, alignment: .center)
                .chartYAxisLabel(p.yLabel, position: .leading)
                .frame(height: 170)
                .accessibilityLabel("Dispersión de \(p.title) con su recta de tendencia")
            }
        }
    }

    private func weeklyCard(_ title: String, icon: String, unit: String, color: Color, domain: ClosedRange<Double>?, data: [(Date, Double)]) -> some View {
        Card(title: title, icon: icon) {
            if data.isEmpty { EmptyNote("Sin datos.") }
            else {
                Chart {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, d in
                        LineMark(x: .value("Semana", d.0), y: .value(unit, d.1)).foregroundStyle(color).interpolationMethod(.monotone)
                        PointMark(x: .value("Semana", d.0), y: .value(unit, d.1)).foregroundStyle(color).symbolSize(30)
                    }
                    if let avg = data.isEmpty ? nil : data.reduce(0, { $0 + $1.1 }) / Double(data.count) {
                        RuleMark(y: .value("Media", avg)).foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .trailing) { Text("media \(fmt(avg, 1))").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                .chartYScale(domain: (domain?.lowerBound ?? (data.map(\.1).min()! - 0.5))...(domain?.upperBound ?? (data.map(\.1).max()! + 0.5)))
                .chartYAxisLabel(unit, position: .leading)
                .frame(height: 180)
                .accessibilityLabel("Gráfica semanal: \(unit)")
            }
        }
    }
}
