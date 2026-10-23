import Charts
import SwiftUI

let medicacionDoses: [Double] = [2.5, 5, 7.5, 10, 12.5, 15]
let injectionSites = ["Abdomen izquierdo", "Abdomen derecho", "Abdomen"]

struct MedicacionView: View {
    @Environment(Store.self) private var store
    @State private var date = Date()
    @State private var dose = 7.5
    @State private var site = "Abdomen izquierdo"
    @State private var note = ""
    @State private var spec: RowSpec?

    var body: some View {
        let m = store.medicacion
        let d = m.daysUntilNext
        let periods = m.periods(weights: store.weight.records)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MissingNoteBanner(module: .medicacion)
                HStack(spacing: 12) {
                    Tile(title: "Último", value: m.last.map { dayLabel($0.date) } ?? "–", note: m.last?.dose)
                    Tile(title: "Próximo", value: m.next.map { dayLabel($0) } ?? "–", note: d.map(relativeDays), tint: (d ?? 0) < 0 ? Brand.bad : nil)
                    Tile(title: "Intervalo", value: "\(m.everyDays) días", note: "editable abajo")
                    Tile(title: "Pinchazos", value: "\(m.doses.count)", note: m.doses.first.map { "desde \(dayLabel($0.date))" })
                }

                let points = m.doses.compactMap { x in x.mg.map { (x.date, $0) } }
                if points.count > 1 {
                    Chart {
                        ForEach(points, id: \.0) { p in
                            AreaMark(x: .value("Día", p.0), y: .value("mg", p.1)).interpolationMethod(.stepEnd).foregroundStyle(Brand.accent.opacity(0.12))
                            LineMark(x: .value("Día", p.0), y: .value("mg", p.1)).interpolationMethod(.stepEnd).foregroundStyle(Brand.accent)
                            PointMark(x: .value("Día", p.0), y: .value("mg", p.1)).foregroundStyle(Brand.accent).symbolSize(20)
                        }
                    }
                    // El eje llega un escalón (2,5 mg) por encima de la dosis más alta, no a 15 fijos.
                    .chartYScale(domain: 0...((points.map(\.1).max() ?? 0) / 2.5 + 1).rounded(.down) * 2.5)
                    .chartYAxis { AxisMarks(values: .stride(by: 2.5)) { v in AxisGridLine(); AxisValueLabel { if let mg = v.as(Double.self) { Text(MD.formatNumber(mg, comma: true)) } } } }
                    .chartYAxisLabel("mg")
                    .frame(height: 130)
                    .accessibilityLabel("Gráfica de dosis")
                    .accessibilityValue(points.suffix(5).map { "\(DayKey.dmy($0.0)) \(fmt($0.1, 1)) mg" }.joined(separator: ", "))
                }

                if periods.count > 0 { periodsCard(periods) }

                Card(title: "Registrar pinchazo", icon: "plus.circle", info: "Se añade una fila a \(VaultPath.medicacion). Zona sugerida para alternar: \(m.suggestedSite).") {
                    HStack(spacing: 20) {
                        DatePicker("Día", selection: $date, in: ...Date(), displayedComponents: .date).fixedSize()
                        Picker("Dosis", selection: $dose) { ForEach(medicacionDoses, id: \.self) { Text(MD.formatNumber($0, comma: true) + " mg").tag($0) } }.fixedSize()
                        Picker("Zona", selection: $site) { ForEach(injectionSites, id: \.self) { Text($0).tag($0) } }.fixedSize()
                        Spacer()
                    }
                    HStack {
                        TextField("Notas", text: $note)
                        Button("Guardar") {
                            store.addDose(date: DayKey.calendar().startOfDay(for: date), dose: dose, site: site, note: note)
                            note = ""
                            site = store.medicacion.suggestedSite
                        }.buttonStyle(.borderedProminent)
                    }
                }

                Card(title: "Intervalo entre pinchazos", icon: "timer", info: "Lo decide tu médico. Cambiarlo recalcula el próximo pinchazo y el aviso de Calendar.") {
                    HStack {
                        Stepper("Cada \(m.everyDays) días", value: Binding(get: { m.everyDays }, set: { store.setProperty(VaultPath.medicacion, key: "cada_dias", value: String($0)) }), in: 1...30)
                        Spacer()
                    }
                }

                Text("Registro").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                    GridRow { Text("Fecha"); Text("Dosis"); Text("Zona"); Text("Notas"); Text("") }.font(.caption).foregroundStyle(.secondary)
                    Divider()
                    ForEach(m.doses.reversed()) { x in
                        GridRow {
                            Text(DayKey.string(x.date)).monospacedDigit(); Text(x.dose); Text(x.site)
                            Text(x.note).foregroundStyle(.secondary).lineLimit(1)
                            EditButton { spec = RowSpec(file: VaultPath.medicacion, mode: .edit(line: x.line), title: "pinchazo") }
                        }
                    }
                }
                Text("La dosis y los cambios los decide tu médico. Esta sección solo registra, calcula y recuerda.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle(store.medicacion.name)
        .sheet(item: $spec) { RowSheet(spec: $0) }
        .onAppear {
            if let mg = m.last?.mg { dose = mg }
            site = m.suggestedSite
        }
    }

    private func periodsCard(_ periods: [DosePeriod]) -> some View {
        Card(title: "Peso por dosis", icon: "chart.bar.xaxis", info: "Peso al empezar y al terminar cada tramo de dosis, con el pesaje más cercano. Orientativo: pesas una vez al mes.") {
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 7) {
                GridRow { Text("Dosis"); Text("Desde"); Text("Pinchazos"); Text("Peso inicial"); Text("Peso final"); Text("Perdidos"); Text("Ritmo") }
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                ForEach(periods) { p in
                    GridRow {
                        Text(MD.formatNumber(p.mg, comma: true) + " mg").fontWeight(.medium)
                        Text(DayKey.dmy(p.start)).monospacedDigit()
                        Text("\(p.count)").monospacedDigit()
                        Text(fmt(p.startKg, unit: " kg")).monospacedDigit()
                        Text(fmt(p.endKg, unit: " kg")).monospacedDigit()
                        Text(fmt(p.lostKg, unit: " kg")).monospacedDigit().foregroundStyle(Brand.accent)
                        Text(p.kgPerMonth.map { fmt($0, unit: " kg/mes") } ?? "–").monospacedDigit()
                    }
                }
            }
        }
    }
}
