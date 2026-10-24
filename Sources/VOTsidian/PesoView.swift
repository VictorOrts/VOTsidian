import Charts
import SwiftUI

struct PesoView: View {
    @Environment(Store.self) private var store
    @State private var allWeights = false
    @State private var date = Date()
    @State private var kg = ""
    @State private var note = ""
    @State private var selected: Date?
    @State private var spec: RowSpec?
    @AppStorage("weightSmoothing") private var smooth = true

    var body: some View {
        let w = store.weight
        let rate = w.ratePerMonth(window: 120)
        // Con un estancamiento, el ritmo de 4 meses tarda en notarlo: se enseña también el de los 2 últimos.
        let recent = w.ratePerMonth(window: 60)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MissingNoteBanner(module: .peso)
                HStack(spacing: 12) {
                    Tile(title: "Último", value: fmt(w.last?.kg, unit: " kg"), note: w.last.map { dayLabel($0.date) })
                    Tile(title: w.gaining ? "Ganados" : "Perdidos", value: fmt(w.achievedKg, unit: " kg"), note: "desde \(fmt(w.initialKg, 0)) kg", tint: Brand.good)
                    Tile(title: "Faltan", value: fmt(w.remainingKg, unit: " kg"), note: w.hasGoal ? "objetivo \(fmt(w.goalKg, 0)) kg" : "sin objetivo en la nota")
                    Tile(title: "Ritmo reciente", value: rate.map { fmtDelta($0, unit: " kg/mes") } ?? "–",
                         note: "pesajes de 4 meses" + (recent.map { " · 2 meses: \(fmtDelta($0, unit: ""))" } ?? ""))
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

                if let p = w.projection() {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Al ritmo de la tendencia suavizada (\(fmtDelta(p.ratePerMonth, unit: " kg/mes")), que pesa más los pesajes recientes) llegarías a \(fmt(w.goalKg, 0)) kg hacia \(DayKey.esLong(p.date, .dateTime.month(.wide).year())).",
                              systemImage: "chart.line.downtrend.xyaxis").font(.callout)
                        if DayKey.string(p.earliest) != DayKey.string(p.latest) {
                            Text("Rango según el ritmo de 2 meses, 4 meses o todo el historial: de \(DayKey.esLong(p.earliest, .dateTime.month(.wide).year())) a \(DayKey.esLong(p.latest, .dateTime.month(.wide).year())).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if w.records.count > 1 { changeChart(w) }

                Card(title: "Registrar peso", icon: "plus.circle", info: "Se añade una fila a \(VaultPath.peso). Pésate una vez al mes, en ayunas.") {
                    HStack {
                        DatePicker("Día", selection: $date, in: ...Date(), displayedComponents: .date).fixedSize()
                        TextField("kg", text: $kg).frame(width: 80)
                        TextField("Notas / sensaciones", text: $note)
                        Button("Guardar") {
                            if let v = MD.number(kg) {
                                store.addWeight(date: DayKey.calendar().startOfDay(for: date), kg: v, note: note)
                                kg = ""; note = ""
                            }
                        }.buttonStyle(.borderedProminent).disabled(MD.number(kg) == nil)
                    }
                }

                Card(title: "Objetivo", icon: "target", info: "Pulsa intro para guardar.") {
                    HStack(spacing: 18) {
                        field("Peso inicial (kg)", "peso_inicial_kg")
                        field("Objetivo (kg)", "objetivo_peso_kg")
                        field("Inicio (DD/MM/AAAA)", "fecha_inicio")
                    }
                }

                milestonesCard(w, rate: rate)
                MedidasCard()
                FotosCard()

                Text("Historial").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                    GridRow { Text("Fecha"); Text("Peso"); Text("Cambio"); Text("Notas"); Text("") }.font(.caption).foregroundStyle(.secondary)
                    Divider()
                    ForEach(Array(w.records.enumerated().reversed().prefix(allWeights ? w.records.count : 60)), id: \.element.id) { i, r in
                        GridRow {
                            Text(DayKey.dmy(r.date)).monospacedDigit()
                            Text(fmt(r.kg, unit: " kg")).monospacedDigit()
                            Text(i > 0 ? fmtDelta(r.kg - w.records[i - 1].kg) : "–").monospacedDigit()
                                .foregroundStyle(i > 0 && r.kg > w.records[i - 1].kg ? Brand.warn : .primary)
                            Text(r.note).foregroundStyle(.secondary)
                            EditButton { spec = RowSpec(file: VaultPath.peso, mode: .edit(line: r.line), title: "pesaje") }
                        }
                    }
                }
                ShowAllButton(total: w.records.count, limit: 60, noun: "pesajes", showAll: $allWeights)
                Button("Abrir la nota Peso") { store.pendingNote = VaultPath.peso }.buttonStyle(.accentLink)
            }
            .padding(24)
            .readableWidth()
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

    private func chartSummary(_ w: WeightData) -> String {
        guard let f = w.records.first, let l = w.records.last else { return "Sin registros" }
        var s = "\(w.records.count) pesajes, de \(fmt(f.kg, unit: " kg")) el \(DayKey.dmy(f.date)) a \(fmt(l.kg, unit: " kg")) el \(DayKey.dmy(l.date)). Objetivo \(fmt(w.goalKg, 0)) kg."
        if let p = w.projection() { s += " Llegada estimada \(DayKey.esLong(p.date, .dateTime.month(.wide).year()))." }
        return s
    }

    private func chartMin(_ w: WeightData) -> Double { (w.records.map(\.kg).min().map { w.hasGoal ? min($0, w.goalKg) : $0 } ?? w.goalKg) - 2 }

    private func mainChart(_ w: WeightData) -> some View {
        let base = chartMin(w)
        let points = thinned(w.records, to: 400)
        return Chart {
            ForEach(points) { r in
                AreaMark(x: .value("Día", r.date), yStart: .value("Base", base), yEnd: .value("kg", r.kg))
                    .foregroundStyle(LinearGradient(colors: [Brand.accent.opacity(0.35), Brand.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Día", r.date), y: .value("kg", r.kg)).foregroundStyle(Brand.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.monotone)
                PointMark(x: .value("Día", r.date), y: .value("kg", r.kg)).foregroundStyle(Brand.accent).symbolSize(28)
            }
            if smooth && w.records.count > 1 {
                ForEach(thinned(w.smoothed(), to: 400)) { r in
                    LineMark(x: .value("Día", r.date), y: .value("kg", r.kg), series: .value("s", "tendencia"))
                        .foregroundStyle(Brand.amber).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3])).interpolationMethod(.monotone)
                }
            }
            ForEach(store.milestones.filter { $0.kg > w.goalKg }) { m in
                RuleMark(y: .value("Hito", m.kg)).foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .annotation(position: .top, alignment: .trailing) { Text("hito \(fmt(m.kg, 0))").font(.caption2).foregroundStyle(.tertiary) }
            }
            if w.hasGoal {
                RuleMark(y: .value("Objetivo", w.goalKg)).foregroundStyle(Brand.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .annotation(position: .top, alignment: .leading) { Text("objetivo \(fmt(w.goalKg, 0)) kg").font(.caption.weight(.semibold)).foregroundStyle(Brand.accent) }
            }
            if let l = w.last, let p = w.projection() {
                ForEach([("proy", p.date), ("proyMin", p.earliest), ("proyMax", p.latest)], id: \.0) { id, d in
                    LineMark(x: .value("Día", l.date), y: .value("kg", l.kg), series: .value("s", id)).foregroundStyle(Brand.info.opacity(id == "proy" ? 0.9 : 0.35)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                    LineMark(x: .value("Día", d), y: .value("kg", w.goalKg), series: .value("s", id)).foregroundStyle(Brand.info.opacity(id == "proy" ? 0.9 : 0.35)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                }
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
                        .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: Brand.radius))
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartXScale(range: .plotDimension(padding: 14))
        .chartYScale(domain: chartMin(w)...(w.records.map(\.kg).max()! + 5))
        .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel() } }
        .frame(height: 320)
        .accessibilityLabel("Gráfica de peso")
        .accessibilityValue(chartSummary(w))
    }

    private func changeChart(_ w: WeightData) -> some View {
        // Solo los últimos 40 pesajes: más barras no se leen y cada una lleva su etiqueta.
        let deltas = Array(w.records.enumerated().dropFirst().map { i, r in (r.date, r.kg - w.records[i - 1].kg) }.suffix(40))
        return Card(title: "Cambio entre pesajes", icon: "chart.bar", info: w.gaining ? "Verde: subiste respecto al pesaje anterior, hacia tu objetivo. Naranja: bajaste." : "Verde: bajaste respecto al pesaje anterior. Naranja: subiste.") {
            Chart {
                ForEach(Array(deltas.enumerated()), id: \.offset) { _, d in
                    BarMark(x: .value("Día", d.0, unit: .day), y: .value("kg", d.1), width: 22)
                        .foregroundStyle(w.isGood(d.1) ? Brand.accent : Brand.warn).cornerRadius(4)
                        .annotation(position: d.1 <= 0 ? .bottom : .top) { Text(fmtDelta(d.1, unit: "")).font(.caption2).foregroundStyle(.secondary) }
                }
                RuleMark(y: .value("Cero", 0)).foregroundStyle(.secondary.opacity(0.4))
            }
            .chartYAxis(.hidden)
            .frame(height: 150)
            .accessibilityLabel("Cambio entre pesajes")
            .accessibilityValue(deltas.suffix(5).map { "\(DayKey.dmy($0.0)) \(fmtDelta($0.1))" }.joined(separator: ", "))
        }
    }

    private func milestonesCard(_ w: WeightData, rate: Double?) -> some View {
        Card(title: "Hitos", icon: "flag") {
            if store.milestones.isEmpty { EmptyNote("Sin hitos. Se ponen en la sección «Hitos» de \(VaultPath.proyecto): nombre, kg y ✅ al llegar.") }
            ForEach(store.milestones) { m in
                let hit = w.records.first { $0.kg <= m.kg }
                HStack {
                    Image(systemName: (hit != nil || m.markedDone) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle((hit != nil || m.markedDone) ? Brand.good : .secondary)
                        .accessibilityLabel((hit != nil || m.markedDone) ? "Conseguido" : "Pendiente")
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
