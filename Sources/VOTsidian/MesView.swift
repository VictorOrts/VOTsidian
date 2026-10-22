import Charts
import SwiftUI

struct MesView: View {
    @Environment(Store.self) private var store
    @State private var offset = 0
    @State private var draft = WeekReview(key: "")
    @State private var base = WeekReview(key: "")
    @State private var saved = false

    private var cal: Calendar { DayKey.calendar() }
    private var start: Date { cal.date(byAdding: .month, value: offset, to: cal.dateInterval(of: .month, for: DayKey.today())!.start)! }
    private var end: Date { DayKey.adding(days: -1, to: cal.date(byAdding: .month, value: 1, to: start)!) }
    private var key: String { String(DayKey.string(start).prefix(7)) }

    var body: some View {
        let inMonth = { (d: Date) in d >= start && d <= end }
        let weights = store.weight.records.filter { inMonth($0.date) }
        let before = store.weight.records.last { $0.date < start }
        let from = before?.kg ?? weights.first?.kg
        let to = weights.last?.kg
        let doses = store.mounjaro.doses.filter { inMonth($0.date) }
        let done = store.tasks.filter { $0.done && ($0.completed.map(inMonth) ?? false) }
        let weekKeys = store.reviews.keys.sorted().filter { k in
            guard let m = k.firstMatch(of: /(\d{4})-W(\d{2})/), let y = Int(m.1), let w = Int(m.2) else { return false }
            var c = DateComponents(); c.yearForWeekOfYear = y; c.weekOfYear = w; c.weekday = 2
            return Calendar(identifier: .iso8601).date(from: c).map(inMonth) ?? false
        }
        let weekPct: [(String, Double)] = weekKeys.compactMap { k in
            guard let r = store.reviews[k], r.totalPossible > 0 else { return nil }
            return (String(k.suffix(3)), Double(r.totalDone) / Double(r.totalPossible) * 100)
        }
        let avg = weekPct.isEmpty ? nil : weekPct.reduce(0) { $0 + $1.1 } / Double(weekPct.count)
        let exists = store.monthReview(key) != nil

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.left").accessibilityLabel("Anterior") }
                    Text(capitalizedFirst(DayKey.esLong(start, .dateTime.month(.wide).year()))).font(.title3.weight(.semibold)).frame(minWidth: 180)
                    Button { offset += 1 } label: { Image(systemName: "chevron.right").accessibilityLabel("Siguiente / abrir") }.disabled(offset >= 0)
                    if offset != 0 { Button("Este mes") { offset = 0 } }
                }

                HStack(spacing: 12) {
                    Tile(title: "Peso", value: (from != nil && to != nil) ? fmtDelta(to! - from!) : "–",
                         note: to.map { "ahora \(fmt($0, unit: " kg"))" + (weights.isEmpty ? "" : " · \(weights.count) \(weights.count == 1 ? "pesaje" : "pesajes")") } ?? "sin pesaje este mes",
                         tint: (from != nil && to != nil && to! < from!) ? Brand.accent : nil)
                    Tile(title: "Pinchazos", value: "\(doses.count)", note: doses.last.map { "dosis \($0.dose)" })
                    Tile(title: "Hábitos", value: avg.map { "\(Int($0)) %" } ?? "–", note: "media de \(weekPct.count) \(weekPct.count == 1 ? "semana" : "semanas")")
                    Tile(title: "Tareas hechas", value: "\(done.count)")
                }

                let moods = store.diarySeries("animo", from: start, to: end)
                let sleeps = store.diarySeries("sueno_h", from: start, to: end)
                if !moods.isEmpty || !sleeps.isEmpty {
                    Card(title: "Ánimo y sueño", icon: "face.smiling") {
                        HStack(spacing: 12) {
                            Tile(title: "Ánimo medio", value: moods.isEmpty ? "–" : fmt(moods.reduce(0) { $0 + $1.1 } / Double(moods.count), unit: " / 5"), note: "\(moods.count) días anotados")
                            Tile(title: "Sueño medio", value: sleeps.isEmpty ? "–" : fmt(sleeps.reduce(0) { $0 + $1.1 } / Double(sleeps.count), unit: " h"), note: "\(sleeps.count) días anotados")
                        }
                        if moods.count > 2 {
                            Chart(moods, id: \.0) { m in
                                BarMark(x: .value("Día", m.0, unit: .day), y: .value("Ánimo", m.1)).foregroundStyle(m.1 >= 4 ? Brand.accent : m.1 <= 2 ? Brand.bad : Brand.warn).cornerRadius(3)
                            }
                            .chartYScale(domain: 0...5).frame(height: 110)
                        }
                        Text("Se anotan en el calendario (panel de cada día) o en Inicio, y se guardan en la nota del día.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if weekPct.count > 1 {
                    Card(title: "Hábitos por semana", icon: "chart.bar") {
                        Chart(weekPct, id: \.0) { w in
                            BarMark(x: .value("Semana", w.0), y: .value("%", w.1)).foregroundStyle(Brand.accent.gradient).cornerRadius(4)
                                .annotation(position: .top) { Text("\(Int(w.1))").font(.caption2).foregroundStyle(.secondary) }
                        }
                        .chartYScale(domain: 0...110).chartYAxis(.hidden).frame(height: 130)
                    }
                }

                if exists {
                    Card(title: "Mirar atrás", icon: "arrow.uturn.backward") {
                        TextField("Logros", text: $draft.logros, axis: .vertical).lineLimit(1...4)
                        LinkPreview(text: draft.logros)
                        if !done.isEmpty {
                            Button { draft.logros = draft.logros.isEmpty ? done.prefix(8).map(\.text).joined(separator: "; ") : draft.logros + "; " + done.prefix(8).map(\.text).joined(separator: "; ") } label: {
                                Label("Rellenar con las tareas hechas", systemImage: "sparkles")
                            }.controlSize(.small)
                        }
                        TextField("Lo que no salió", text: $draft.noSalio, axis: .vertical).lineLimit(1...4)
                        LinkPreview(text: draft.noSalio)
                    }
                    Card(title: "Mes siguiente", icon: "target") {
                        ForEach(0..<3, id: \.self) { i in
                            TextField("Objetivo \(i + 1)", text: $draft.objetivos[i])
                            LinkPreview(text: draft.objetivos[i])
                        }
                        Button { store.addTasks(draft.objetivos.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { ($0, DayKey.adding(days: 30, to: end)) }) } label: {
                            Label("Convertir objetivos en tareas", systemImage: "checklist")
                        }.controlSize(.small).disabled(draft.objetivos.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                    }
                    HStack {
                        Button("Guardar revisión") { saveMonth(quiet: false) }
                            .keyboardShortcut("s", modifiers: .command).buttonStyle(.borderedProminent)
                        if saved { Label("Guardado", systemImage: "checkmark.circle.fill").foregroundStyle(Brand.good) }
                        Spacer()
                        Button("Editar la nota completa") { store.pendingNote = store.monthReviewFile(key) }.buttonStyle(.accentLink)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Sin revisión para \(key)", systemImage: "calendar.badge.plus")
                    } description: { Text("Se crea Revisiones/Revisión mensual \(key).md.") } actions: {
                        Button("Crear revisión") { store.createMonthReview(key: key, monthStart: start) }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Revisión mensual")
        .onAppear { if offset == 0, store.monthReview(key) == nil { store.createMonthReview(key: key, monthStart: start) }; load() }
        .onChange(of: key) { load() }
        .onChange(of: store.revision) { if draft == base { load() } }
        .onChange(of: draft) { if draft != base { saved = false } }
        .autosave(on: draft) { if draft != base, store.monthReview(key) != nil { saveMonth(quiet: true) } }
    }

    private func saveMonth(quiet: Bool) {
        store.saveMonthText(key: key, draft, quiet: quiet)
        base = draft; saved = true
    }

    private func load() { let r = store.monthReview(key) ?? WeekReview(key: key); draft = r; base = r; saved = false }
}
