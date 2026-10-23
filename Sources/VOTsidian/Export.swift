import Charts
import SwiftUI

enum CSV {
    /// Una fila CSV: entrecomilla lo que lleve comas, comillas o saltos de línea.
    static func row(_ cells: [String]) -> String {
        cells.map { c in
            if c.contains(",") || c.contains("\"") || c.contains("\n") { return "\"" + c.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            return c
        }.joined(separator: ",")
    }

    static func file(_ header: [String], _ rows: [[String]]) -> String {
        ([row(header)] + rows.map(row)).joined(separator: "\n") + "\n"
    }

    static func num(_ v: Double?) -> String { v.map { MD.formatNumber($0) } ?? "" }
}

struct YearStats {
    var year: Int
    var weights: [WeightRecord]
    var dosesByMg: [(mg: Double, count: Int)]
    var injections: Int
    var habitByMonth: [(month: Int, pct: Double)]
    var tasksDone: Int
    var moodAvg: Double?
    var sleepAvg: Double?
    var diaryDays: Int

    var firstKg: Double? { weights.first?.kg }
    var lastKg: Double? { weights.last?.kg }
    var deltaKg: Double? { zip(firstKg, lastKg).map { $1 - $0 } }
}

private func zip(_ a: Double?, _ b: Double?) -> (Double, Double)? { a.flatMap { x in b.map { (x, $0) } } }

extension Store {
    func yearStats(_ year: Int) -> YearStats {
        let cal = DayKey.calendar()
        func inYear(_ d: Date) -> Bool { cal.component(.year, from: d) == year }
        let doses = mounjaro.doses.filter { inYear($0.date) }
        var byMg: [Double: Int] = [:]
        for d in doses { if let mg = d.mg { byMg[mg, default: 0] += 1 } }
        var perMonth: [Int: [Double]] = [:]
        for (k, r) in reviews where r.totalPossible > 0 {
            guard let m = k.firstMatch(of: /(\d{4})-W(\d{2})/), let y = Int(m.1), let w = Int(m.2) else { continue }
            var c = DateComponents(); c.yearForWeekOfYear = y; c.weekOfYear = w; c.weekday = 2
            guard let monday = Calendar(identifier: .iso8601).date(from: c), inYear(monday) else { continue }
            perMonth[cal.component(.month, from: monday), default: []].append(Double(r.totalDone) / Double(r.totalPossible) * 100)
        }
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = cal.date(from: DateComponents(year: year, month: 12, day: 31))!
        let moods = diarySeries("animo", from: start, to: end)
        let sleeps = diarySeries("sueno_h", from: start, to: end)
        return YearStats(
            year: year, weights: weight.records.filter { inYear($0.date) },
            dosesByMg: byMg.map { (mg: $0.key, count: $0.value) }.sorted { $0.mg < $1.mg }, injections: doses.count,
            habitByMonth: perMonth.map { (month: $0.key, pct: $0.value.reduce(0, +) / Double($0.value.count)) }.sorted { $0.month < $1.month },
            tasksDone: tasks.filter { $0.done && ($0.completed.map(inYear) ?? false) }.count,
            moodAvg: moods.isEmpty ? nil : moods.reduce(0) { $0 + $1.1 } / Double(moods.count),
            sleepAvg: sleeps.isEmpty ? nil : sleeps.reduce(0) { $0 + $1.1 } / Double(sleeps.count),
            diaryDays: notes.filter { $0.path.hasPrefix("Diario/") && (DayKey.date($0.name).map(inYear) ?? false) }.count)
    }

    /// Escribe tus datos en CSV (peso, pinchazos, medidas, hábitos, tareas, gastos, ánimo y sueño) y un resumen. Devuelve los archivos creados.
    @discardableResult
    func exportData(to dir: URL) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var made: [URL] = []
        func write(_ name: String, _ text: String) throws {
            let u = dir.appendingPathComponent(name)
            try text.write(to: u, atomically: true, encoding: .utf8)
            made.append(u)
        }
        try write("peso.csv", CSV.file(["fecha", "peso_kg", "notas"], weight.records.map { [DayKey.string($0.date), CSV.num($0.kg), $0.note] }))
        try write("mounjaro.csv", CSV.file(["fecha", "dosis_mg", "zona", "notas"], mounjaro.doses.map { [DayKey.string($0.date), CSV.num($0.mg), $0.site, $0.note] }))
        let (_, measures) = Measures.parse(read(Measures.file))
        if !measures.isEmpty {
            try write("medidas.csv", CSV.file(["fecha"] + Measures.fields + ["notas"], measures.map { m in [DayKey.string(m.date)] + Measures.fields.map { f in CSV.num(m.values[f]) } + [m.note] }))
        }
        var habitRows: [[String]] = []
        for key in reviews.keys.sorted() {
            guard let r = reviews[key] else { continue }
            for h in r.habits { habitRows.append([key, h.name] + h.days.map { $0 ? "1" : "0" } + ["\(h.count)"]) }
        }
        try write("habitos.csv", CSV.file(["semana", "habito", "L", "M", "X", "J", "V", "S", "D", "dias"], habitRows))
        try write("tareas.csv", CSV.file(["nota", "tarea", "fecha_limite", "prioridad", "hecha", "fecha_hecha"],
                                         tasks.map { [$0.noteName, $0.text, $0.due.map(DayKey.string) ?? "", ["", "baja", "media", "alta"][$0.priority], $0.done ? "1" : "0", $0.completed.map(DayKey.string) ?? ""] }))
        // Gastos: cada movimiento de todas las notas de mes, con su mes por si la fecha escrita a mano es de otro.
        let moves = budgetMonths.compactMap { budget($0) }.flatMap { b in b.moves.map { [b.month, DayKey.string($0.date), CSV.num($0.amount), $0.category, $0.note] } }
        if !moves.isEmpty { try write("gastos.csv", CSV.file(["mes", "fecha", "importe_eur", "partida", "nota"], moves)) }
        // El resumen anual, mes a mes: lo mismo que Gastos → Año.
        let months = budgetYears.sorted().flatMap { budgetYear($0).months }
        if !months.isEmpty {
            try write("resumen_mensual.csv", CSV.file(["mes", "ingresos_eur", "gastos_eur", "queda_eur", "previsto"],
                                                     months.map { [$0.month, CSV.num($0.income), CSV.num($0.spent), CSV.num($0.left), $0.planned ? "1" : "0"] }))
        }
        var diary: [[String]] = []
        for n in notes where n.path.hasPrefix("Diario/") {
            guard let d = DayKey.date(n.name) else { continue }
            let a = diaryValue(d, "animo"), s = diaryValue(d, "sueno_h")
            if a != nil || s != nil { diary.append([n.name, CSV.num(a), CSV.num(s)]) }
        }
        try write("animo_sueno.csv", CSV.file(["fecha", "animo", "sueno_h"], diary.sorted { $0[0] < $1[0] }))
        try write("resumen.md", doctorSummary())
        return made
    }

    /// Copia comprimida de todas las notas.
    func exportNotesZip(to zip: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--keepParent", root.path, zip.path]
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }
}

/// Página del resumen anual (se exporta a PDF).
struct YearSummaryView: View {
    let stats: YearStats
    let vaultName: String

    private let months = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Resumen \(String(stats.year))").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Generado el \(DayKey.dmy(Date())) · \(vaultName)").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                tile("Peso", stats.deltaKg.map { fmtDelta($0) } ?? "–", stats.lastKg.map { "ahora \(fmt($0, unit: " kg"))" } ?? "sin pesajes")
                tile("Pinchazos", "\(stats.injections)", stats.dosesByMg.map { "\(MD.formatNumber($0.mg, comma: true)) mg ×\($0.count)" }.joined(separator: " · "))
                tile("Tareas hechas", "\(stats.tasksDone)", "")
                tile("Ánimo", stats.moodAvg.map { fmt($0, unit: " / 5") } ?? "–", stats.sleepAvg.map { "sueño " + fmt($0, unit: " h") } ?? "")
            }
            if stats.weights.count > 1 {
                Text("Peso (kg)").font(.headline)
                Chart(stats.weights) { w in
                    LineMark(x: .value("Día", w.date), y: .value("kg", w.kg)).foregroundStyle(Brand.accent).interpolationMethod(.monotone)
                    PointMark(x: .value("Día", w.date), y: .value("kg", w.kg)).foregroundStyle(Brand.accent)
                }
                .chartYScale(domain: ((stats.weights.map(\.kg).min() ?? 0) - 2)...((stats.weights.map(\.kg).max() ?? 0) + 2))
                .frame(height: 190)
            }
            if !stats.habitByMonth.isEmpty {
                Text("Cumplimiento de hábitos por mes (%)").font(.headline)
                Chart(stats.habitByMonth, id: \.month) { h in
                    BarMark(x: .value("Mes", months[max(0, min(11, h.month - 1))]), y: .value("%", h.pct)).foregroundStyle(Brand.accent.gradient)
                }
                .chartYScale(domain: 0...100).frame(height: 150)
            }
            if !stats.weights.isEmpty {
                Text("Pesajes").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                    ForEach(stats.weights) { w in GridRow { Text(DayKey.dmy(w.date)).monospacedDigit(); Text(fmt(w.kg, unit: " kg")).monospacedDigit(); Text(w.note).foregroundStyle(.secondary) } }
                }.font(.callout)
            }
            Text("Datos orientativos de tus notas. Confírmalos con tu médico o dietista.").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(36)
        .frame(width: 620, alignment: .leading)
    }

    private func tile(_ title: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading).padding(10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Brand.radius))
    }
}

@MainActor
enum PDFExport {
    /// Dibuja una vista en un PDF de una sola página (alta lo que haga falta).
    static func write<V: View>(_ view: V, to url: URL) {
        let content = view.background(Color.white).environment(\.colorScheme, .light).foregroundStyle(Color.black)
        let renderer = ImageRenderer(content: content)
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
    }
}
