import Charts
import SwiftUI

let mounjaroDoses: [Double] = [2.5, 5, 7.5, 10, 12.5, 15]
let injectionSites = ["Abdomen izquierdo", "Abdomen derecho", "Abdomen"]

struct MounjaroView: View {
    @Environment(Store.self) private var store
    @State private var date = Date()
    @State private var dose = 7.5
    @State private var site = "Abdomen izquierdo"
    @State private var note = ""
    @State private var spec: RowSpec?

    var body: some View {
        let m = store.mounjaro
        let d = m.daysUntilNext
        let periods = m.periods(weights: store.weight.records)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Tile(title: "Último", value: m.last.map { DayKey.dmy($0.date) } ?? "–", note: m.last?.dose)
                    Tile(title: "Próximo", value: m.next.map { shortDate($0) } ?? "–", note: d.map(relativeDays), tint: (d ?? 0) < 0 ? Brand.bad : nil)
                    Tile(title: "Intervalo", value: "\(m.everyDays) días", note: "editable abajo")
                    Tile(title: "Pinchazos", value: "\(m.doses.count)", note: m.doses.first.map { "desde \(DayKey.dmy($0.date))" })
                }

                let points = m.doses.compactMap { x in x.mg.map { (x.date, $0) } }
                if points.count > 1 {
                    Chart {
                        ForEach(points, id: \.0) { p in
                            LineMark(x: .value("Día", p.0), y: .value("mg", p.1)).interpolationMethod(.stepEnd).foregroundStyle(.tint)
                            PointMark(x: .value("Día", p.0), y: .value("mg", p.1)).foregroundStyle(.tint)
                        }
                    }
                    .chartYScale(domain: 0...(max(15, points.map(\.1).max() ?? 15)))
                    .chartYAxisLabel("mg")
                    .frame(height: 170)
                    .accessibilityLabel("Gráfica de dosis")
                    .accessibilityValue(points.suffix(5).map { "\(DayKey.dmy($0.0)) \(fmt($0.1, 1)) mg" }.joined(separator: ", "))
                }

                if periods.count > 0 { periodsCard(periods) }

                Card(title: "Registrar pinchazo", icon: "plus.circle") {
                    HStack {
                        DatePicker("Día", selection: $date, in: ...Date(), displayedComponents: .date).frame(width: 220)
                        Picker("Dosis", selection: $dose) { ForEach(mounjaroDoses, id: \.self) { Text(MD.formatNumber($0, comma: true) + " mg").tag($0) } }.frame(width: 160)
                        Picker("Zona", selection: $site) { ForEach(injectionSites, id: \.self) { Text($0).tag($0) } }.frame(width: 230)
                    }
                    HStack {
                        TextField("Notas", text: $note)
                        Button("Guardar") {
                            store.addDose(date: DayKey.calendar().startOfDay(for: date), dose: dose, site: site, note: note)
                            note = ""
                            site = store.mounjaro.suggestedSite
                        }.buttonStyle(.borderedProminent)
                    }
                    Text("Se añade una fila a Cambio físico/Mounjaro.md. Zona sugerida para alternar: \(m.suggestedSite).").font(.caption).foregroundStyle(.secondary)
                }

                Card(title: "Intervalo entre pinchazos", icon: "timer") {
                    HStack {
                        Stepper("Cada \(m.everyDays) días", value: Binding(get: { m.everyDays }, set: { store.setProperty(VaultPath.mounjaro, key: "cada_dias", value: String($0)) }), in: 1...30)
                        Spacer()
                    }
                    Text("Lo decide tu médico. Cambiarlo recalcula el próximo pinchazo y el aviso de Calendar.").font(.caption).foregroundStyle(.secondary)
                }

                Text("Registro").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                    GridRow { Text("Fecha"); Text("Dosis"); Text("Zona"); Text("Notas"); Text("") }.font(.caption).foregroundStyle(.secondary)
                    Divider()
                    ForEach(m.doses.reversed()) { x in
                        GridRow {
                            Text(DayKey.string(x.date)).monospacedDigit(); Text(x.dose); Text(x.site)
                            Text(x.note).foregroundStyle(.secondary).lineLimit(1)
                            EditButton { spec = RowSpec(file: VaultPath.mounjaro, mode: .edit(line: x.line), title: "pinchazo") }
                        }
                    }
                }
                Text("La dosis y los cambios los decide tu médico. Esta sección solo registra, calcula y recuerda.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .navigationTitle("Mounjaro")
        .sheet(item: $spec) { RowSheet(spec: $0) }
        .onAppear {
            if let mg = m.last?.mg { dose = mg }
            site = m.suggestedSite
        }
    }

    private func periodsCard(_ periods: [DosePeriod]) -> some View {
        Card(title: "Peso por dosis", icon: "chart.bar.xaxis") {
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
                        Text(p.kgPerMonth.map { String(format: "%.1f kg/mes", $0) } ?? "–").monospacedDigit()
                    }
                }
            }
            Text("Peso al empezar y al terminar cada tramo de dosis, con el pesaje más cercano. Orientativo: pesas una vez al mes.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
