import Charts
import SwiftUI

struct PesoView: View {
    @Environment(Store.self) private var store
    @State private var date = Date()
    @State private var kg = ""
    @State private var note = ""
    @State private var selected: Date?
    @State private var spec: RowSpec?
    @AppStorage("weightSmoothing") private var smooth = true

    var body: some View {
        let w = store.weight
        let rate = w.ratePerMonth(window: 120)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Tile(title: "Último", value: fmt(w.last?.kg, unit: " kg"), note: w.last.map { DayKey.dmy($0.date) })
                    Tile(title: "Perdidos", value: fmt(w.lostKg, unit: " kg"), note: "desde \(fmt(w.initialKg, 0)) kg", tint: .green)
                    Tile(title: "Faltan", value: fmt(w.remainingKg, unit: " kg"), note: "objetivo \(fmt(w.goalKg, 0)) kg")
                    Tile(title: "Ritmo reciente", value: rate.map { fmtDelta($0, unit: " kg/mes") } ?? "–", note: "últimos 4 meses")
                }

                if w.records.isEmpty {
                    ContentUnavailableView("Sin registros", systemImage: "scalemass")
                } else {
                    mainChart(w)
                    if w.records.count > 1 {
                        Toggle("Mostrar tendencia suavizada", isOn: $smooth).font(.callout)
                        if smooth, let t = w.smoothed().last {
                            Text("Tendencia: \(fmt(t.kg, unit: " kg")). Suaviza las subidas y bajadas puntuales (agua, comida, hora) para ver el rumbo real.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if let d = w.projectedGoalDate(), let r = rate {
                    Label("Al ritmo de los últimos 4 meses (\(fmtDelta(r, unit: " kg/mes"))) llegarías a \(fmt(w.goalKg, 0)) kg hacia \(DayKey.esLong(d, .dateTime.month(.wide).year())).",
                          systemImage: "chart.line.downtrend.xyaxis").font(.callout)
                }

                if w.records.count > 1 { changeChart(w) }

                Card(title: "Registrar peso", icon: "plus.circle") {
                    HStack {
                        DatePicker("Día", selection: $date, in: ...Date(), displayedComponents: .date).frame(width: 220)
                        TextField("kg", text: $kg).frame(width: 80)
                        TextField("Notas / sensaciones", text: $note)
                        Button("Guardar") {
                            if let v = MD.number(kg) {
                                store.addWeight(date: DayKey.calendar().startOfDay(for: date), kg: v, note: note)
                                kg = ""; note = ""
                            }
                        }.buttonStyle(.borderedProminent).disabled(MD.number(kg) == nil)
                    }
                    Text("Se añade una fila a Cambio físico/Peso.md. Pésate una vez al mes, en ayunas.").font(.caption).foregroundStyle(.secondary)
                }

                Card(title: "Objetivo", icon: "target") {
                    HStack(spacing: 18) {
                        field("Peso inicial (kg)", "peso_inicial_kg")
                        field("Objetivo (kg)", "objetivo_peso_kg")
                        field("Inicio (DD/MM/AAAA)", "fecha_inicio")
                    }
                    Text("Pulsa intro para guardar.").font(.caption).foregroundStyle(.secondary)
                }

                milestonesCard(w, rate: rate)
                MedidasCard()
                FotosCard()

                Text("Historial").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                    GridRow { Text("Fecha"); Text("Peso"); Text("Cambio"); Text("Notas"); Text("") }.font(.caption).foregroundStyle(.secondary)
                    Divider()
                    ForEach(Array(w.records.enumerated().reversed()), id: \.element.id) { i, r in
                        GridRow {
                            Text(DayKey.dmy(r.date)).monospacedDigit()
                            Text(fmt(r.kg, unit: " kg")).monospacedDigit()
                            Text(i > 0 ? fmtDelta(r.kg - w.records[i - 1].kg) : "–").monospacedDigit()
                                .foregroundStyle(i > 0 && r.kg > w.records[i - 1].kg ? Color.orange : .primary)
                            Text(r.note).foregroundStyle(.secondary)
                            EditButton { spec = RowSpec(file: VaultPath.peso, mode: .edit(line: r.line), title: "pesaje") }
                        }
                    }
                }
                Button("Abrir la nota Peso") { store.pendingNote = VaultPath.peso }.buttonStyle(.link)
            }
            .padding(24)
        }
        .navigationTitle("Peso")
        .sheet(item: $spec) { RowSheet(spec: $0) }
    }

    private func field(_ label: String, _ key: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            PropertyField(file: VaultPath.peso, key: key, width: 150)
        }
    }

    // MARK: Gráficas

    private var hovered: WeightRecord? {
        guard let s = selected else { return nil }
        return store.weight.records.min { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) }
    }

    private func chartMin(_ w: WeightData) -> Double { min(w.goalKg, w.records.map(\.kg).min() ?? w.goalKg) - 2 }

    private func mainChart(_ w: WeightData) -> some View {
        Chart {
            ForEach(w.records) { r in
                AreaMark(x: .value("Día", r.date), yStart: .value("Base", chartMin(w)), yEnd: .value("kg", r.kg))
                    .foregroundStyle(LinearGradient(colors: [Brand.accent.opacity(0.35), Brand.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Día", r.date), y: .value("kg", r.kg)).foregroundStyle(Brand.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.monotone)
                PointMark(x: .value("Día", r.date), y: .value("kg", r.kg)).foregroundStyle(Brand.accent).symbolSize(40)
            }
            if smooth && w.records.count > 1 {
                ForEach(w.smoothed()) { r in
                    LineMark(x: .value("Día", r.date), y: .value("kg", r.kg), series: .value("s", "tendencia"))
                        .foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3])).interpolationMethod(.monotone)
                }
            }
            ForEach(store.milestones.filter { $0.kg > w.goalKg }) { m in
                RuleMark(y: .value("Hito", m.kg)).foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .annotation(position: .top, alignment: .leading) { Text("\(fmt(m.kg, 0)) kg").font(.caption2).foregroundStyle(.secondary) }
            }
            RuleMark(y: .value("Objetivo", w.goalKg)).foregroundStyle(Brand.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .annotation(position: .top, alignment: .leading) { Text("objetivo \(fmt(w.goalKg, 0)) kg").font(.caption.weight(.semibold)).foregroundStyle(Brand.accent) }
            if let l = w.last, let d = w.projectedGoalDate() {
                LineMark(x: .value("Día", l.date), y: .value("kg", l.kg), series: .value("s", "proy")).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                LineMark(x: .value("Día", d), y: .value("kg", w.goalKg), series: .value("s", "proy")).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
            }
            if let l = w.last {
                PointMark(x: .value("Día", l.date), y: .value("kg", l.kg)).foregroundStyle(Brand.accent).symbolSize(120)
                    .annotation(position: .top) { Text(fmt(l.kg, unit: " kg")).font(.caption.bold()) }
            }
            if let r = hovered {
                RuleMark(x: .value("Día", r.date)).foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DayKey.dmy(r.date)).font(.caption).foregroundStyle(.secondary)
                            Text(fmt(r.kg, unit: " kg")).font(.callout.bold())
                            if let i = w.records.firstIndex(of: r), i > 0 { Text(fmtDelta(r.kg - w.records[i - 1].kg)).font(.caption) }
                        }
                        .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartXScale(range: .plotDimension(padding: 14))
        .chartYScale(domain: chartMin(w)...(w.records.map(\.kg).max()! + 5))
        .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel() } }
        .frame(height: 320)
    }

    private func changeChart(_ w: WeightData) -> some View {
        // Solo los últimos 40 pesajes: más barras no se leen y cada una lleva su etiqueta.
        let deltas = Array(w.records.enumerated().dropFirst().map { i, r in (r.date, r.kg - w.records[i - 1].kg) }.suffix(40))
        return Card(title: "Cambio entre pesajes", icon: "chart.bar") {
            Chart {
                ForEach(Array(deltas.enumerated()), id: \.offset) { _, d in
                    BarMark(x: .value("Día", d.0, unit: .day), y: .value("kg", d.1), width: 22)
                        .foregroundStyle(d.1 <= 0 ? Brand.accent : Brand.warn).cornerRadius(4)
                        .annotation(position: d.1 <= 0 ? .bottom : .top) { Text(fmtDelta(d.1, unit: "")).font(.caption2).foregroundStyle(.secondary) }
                }
                RuleMark(y: .value("Cero", 0)).foregroundStyle(.secondary.opacity(0.4))
            }
            .chartYAxis(.hidden)
            .frame(height: 150)
            Text("Verde: bajaste respecto al pesaje anterior. Naranja: subiste.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func milestonesCard(_ w: WeightData, rate: Double?) -> some View {
        Card(title: "Hitos", icon: "flag") {
            if store.milestones.isEmpty { Text("Sin hitos en Proyectos/Cambio físico 2026.").foregroundStyle(.secondary) }
            ForEach(store.milestones) { m in
                let hit = w.records.first { $0.kg <= m.kg }
                HStack {
                    Image(systemName: (hit != nil || m.markedDone) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle((hit != nil || m.markedDone) ? Color.green : .secondary)
                    Text(m.name)
                    Spacer()
                    if let hit { Text(DayKey.dmy(hit.date)).font(.caption).foregroundStyle(.secondary) }
                    else if let l = w.last, let r = rate, r < 0 {
                        let d = DayKey.adding(days: Int((l.kg - m.kg) / -r * 30.4), to: l.date)
                        Text("≈ \(DayKey.esLong(d, .dateTime.month(.abbreviated).year()))").font(.caption).foregroundStyle(.secondary)
                    } else { Text("pendiente").font(.caption).foregroundStyle(.secondary) }
                    EditButton { spec = RowSpec(file: VaultPath.proyecto, mode: .edit(line: m.line), title: "hito") }
                }
            }
            if let last = store.milestones.last {
                Button {
                    spec = RowSpec(file: VaultPath.proyecto, mode: store.addMode(file: VaultPath.proyecto, afterRowLine: last.line), title: "hitos")
                } label: { Label("Añadir hito", systemImage: "plus") }.buttonStyle(.borderless).font(.callout)
            }
        }
    }
}
