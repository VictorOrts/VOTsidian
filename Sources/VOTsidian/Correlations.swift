import Charts
import SwiftUI

/// Una semana (lunes a domingo) con lo que se midió en ella.
struct WeekPoint: Equatable {
    var start: Date
    var mood: Double?
    var sleep: Double?
    var kgChange: Double?   // peso al final de la semana menos peso al final de la anterior
    var mg: Double?         // dosis vigente al final de la semana
}

struct CorrelationPair: Identifiable, Equatable {
    var title: String
    var r: Double?
    var n: Int
    var id: String { title }

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

    /// Semanas desde el primer pesaje hasta hoy. `mood` y `sleep` devuelven la media entre dos fechas (ambas incluidas).
    static func weeks(weights: [WeightRecord], doses: [Dose], today: Date,
                      mood: (Date, Date) -> Double?, sleep: (Date, Date) -> Double?) -> [WeekPoint] {
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
            out.append(WeekPoint(start: start, mood: mood(start, end), sleep: sleep(start, end), kgChange: change, mg: mg(upTo: end)))
            start = DayKey.adding(days: 7, to: start)
        }
        return out
    }

    private static func pair(_ title: String, _ points: [WeekPoint], _ a: (WeekPoint) -> Double?, _ b: (WeekPoint) -> Double?) -> CorrelationPair {
        let both = points.compactMap { p -> (Double, Double)? in
            guard let x = a(p), let y = b(p) else { return nil }
            return (x, y)
        }
        return CorrelationPair(title: title, r: pearson(both.map(\.0), both.map(\.1)), n: both.count)
    }

    static func pairs(_ points: [WeekPoint]) -> [CorrelationPair] {
        [pair("Sueño ↔ ánimo", points, \.sleep, \.mood),
         pair("Dosis ↔ cambio de peso semanal", points, \.mg, \.kgChange),
         pair("Sueño ↔ cambio de peso semanal", points, \.sleep, \.kgChange),
         pair("Ánimo ↔ cambio de peso semanal", points, \.mood, \.kgChange)]
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
        return Correlations.weeks(weights: weight.records, doses: mounjaro.doses, today: today, mood: avg("animo"), sleep: avg("sueno_h"))
    }
}

struct CorrelacionesView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let points = store.weekPoints()
        let pairs = Correlations.pairs(points)
        let doses = store.mounjaro.doses.sorted { $0.date < $1.date }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Aquí se cruzan peso, dosis, ánimo y sueño por semanas. Una relación no prueba que una cosa cause la otra: sirve para sospechar y comentarlo con tu médico.")
                    .font(.callout).foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ForEach(pairs) { p in
                        Tile(title: p.title, value: p.r.map { String(format: "%+.2f", $0).replacingOccurrences(of: ".", with: ",") } ?? "–",
                             note: p.reading + (p.r != nil ? " (\(p.n) semanas)" : ""))
                    }
                }

                Card(title: "Peso y dosis", icon: "scalemass") {
                    if store.weight.records.count < 2 { Text("Faltan registros de peso.").foregroundStyle(.secondary) }
                    else {
                        Chart {
                            ForEach(Array(doses.enumerated()), id: \.offset) { i, d in
                                let end = i + 1 < doses.count ? doses[i + 1].date : DayKey.today()
                                RectangleMark(xStart: .value("Desde", d.date), xEnd: .value("Hasta", end))
                                    .foregroundStyle((i % 2 == 0 ? Color.accentColor : Color.orange).opacity(0.10))
                                    .annotation(position: .top, alignment: .leading) { Text(d.dose).font(.caption2).foregroundStyle(.secondary) }
                            }
                            ForEach(store.weight.records) { r in
                                LineMark(x: .value("Fecha", r.date), y: .value("kg", r.kg))
                                PointMark(x: .value("Fecha", r.date), y: .value("kg", r.kg)).symbolSize(20)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 220)
                        .accessibilityLabel("Gráfica de peso con las dosis de Mounjaro como bandas")
                    }
                }

                Card(title: "Ánimo y sueño por semana", icon: "moon.zzz") {
                    let withData = points.filter { $0.mood != nil || $0.sleep != nil }
                    if withData.isEmpty { Text("Aún no hay ánimo ni sueño en las notas del día.").foregroundStyle(.secondary) }
                    else {
                        Chart {
                            ForEach(withData, id: \.start) { p in
                                if let m = p.mood { LineMark(x: .value("Semana", p.start), y: .value("Ánimo (1-5)", m), series: .value("Serie", "Ánimo")).foregroundStyle(by: .value("Serie", "Ánimo")) }
                                if let s = p.sleep { LineMark(x: .value("Semana", p.start), y: .value("Sueño (h)", s), series: .value("Serie", "Sueño (h)")).foregroundStyle(by: .value("Serie", "Sueño (h)")) }
                            }
                        }
                        .frame(height: 200)
                        .accessibilityLabel("Gráfica semanal de ánimo y horas de sueño")
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Correlaciones")
    }
}
