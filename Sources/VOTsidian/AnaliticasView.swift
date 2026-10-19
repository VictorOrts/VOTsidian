import Charts
import SwiftUI

struct AnaliticasView: View {
    @Environment(Store.self) private var store
    @State private var selected: String?
    @State private var date = Date()
    @State private var rows = [LabRowInput()]
    @State private var spec: RowSpec?
    @State private var message = ""

    var body: some View {
        let params = store.labParameters
        let out = store.labsOutOfRange
        let current = params.first { $0.id == selected } ?? params.first(where: { $0.latest.status.outOfRange }) ?? params.first

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !store.labsExist {
                    emptyState
                } else {
                    HStack(spacing: 12) {
                        Tile(title: "Parámetros", value: "\(params.count)", note: "con resultados")
                        Tile(title: "Fuera de rango", value: "\(out.count)", note: "en el último resultado", tint: out.isEmpty ? Brand.accent : Brand.warn)
                        Tile(title: "Última analítica", value: store.labs.map(\.date).max().map { DayKey.dmy($0) } ?? "–",
                             note: store.labs.map(\.date).max().map { relativeDays(DayKey.days(from: DayKey.today(), to: $0)) })
                    }
                    if !out.isEmpty {
                        Card(title: "Para comentar con tu médico", icon: "exclamationmark.triangle") {
                            ForEach(out) { r in
                                HStack {
                                    Text(r.name).fontWeight(.medium)
                                    pill(r.status)
                                    Text(r.valueText).monospacedDigit()
                                    if !r.refText.isEmpty { Text("ref. \(r.refText)").font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    Text(DayKey.dmy(r.date)).font(.caption).foregroundStyle(.secondary)
                                }
                                if !r.note.isEmpty { Text(r.note).font(.caption).foregroundStyle(.secondary) }
                            }
                            Text("Orientativo: los rangos los marca tu laboratorio y la interpretación es de tu médico.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12, alignment: .top)], spacing: 12) {
                        ForEach(params) { p in parameterCard(p, isSelected: p.id == current?.id) }
                    }
                    if let current { detail(current) }
                    newForm(params)
                    Button("Abrir la nota Analíticas") { store.pendingNote = Labs.file }.buttonStyle(.link)
                }
            }
            .padding(24)
        }
        .navigationTitle("Analíticas")
        .sheet(item: $spec) { RowSheet(spec: $0) }
    }

    // MARK: Sin datos

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            ContentUnavailableView {
                Label("Seguimiento de analíticas", systemImage: "testtube.2")
            } description: {
                Text("Guarda cada valor de tus análisis (glucosa, colesterol, HDL, CK…) con su referencia, mira cómo evoluciona y detecta lo que sale fuera de rango.")
            } actions: {
                Button("Activar analíticas") { store.ensureLabs() }.buttonStyle(.borderedProminent)
            }
            Card(title: "Valores que ya tienes anotados", icon: "text.badge.checkmark") {
                Text("Tu nota Médico menciona estos valores del análisis del 18/09/2026. Puedes añadirlos con un clic y corregirlos después.").foregroundStyle(.secondary)
                ForEach(Labs.seed, id: \.name) { s in
                    Text("• \(s.name): \(s.value) \(s.unit)" + (s.estado.isEmpty ? "" : " (\(s.estado))") + (s.max.isEmpty ? "" : " · ref. \(s.min.isEmpty ? "≤" : s.min + "–")\(s.max)")).font(.callout)
                }
                Button("Activar y añadir estos valores") { store.addSeedLabs() }
            }
        }
    }

    // MARK: Piezas

    private func pill(_ s: LabStatus) -> some View {
        Text(s.label).font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 2)
            .background(s.color.opacity(0.2), in: Capsule()).foregroundStyle(s.color)
    }

    private func parameterCard(_ p: LabParameter, isSelected: Bool) -> some View {
        let l = p.latest
        return Button { selected = p.id } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(p.name).font(.subheadline.weight(.semibold)).lineLimit(1); Spacer(); pill(l.status) }
                Text(l.valueText).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                HStack {
                    if !l.refText.isEmpty { Text("ref. \(l.refText)").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if let prev = p.previous, let a = l.value, let b = prev.value {
                        Text(String(format: "%+.1f", a - b)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if p.results.count > 1 {
                    Chart(p.results) { r in
                        if let v = r.value { LineMark(x: .value("Día", r.date), y: .value("v", v)).foregroundStyle(l.status.color) }
                    }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 30)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Brand.accent.opacity(0.13) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(l.status.outOfRange ? Brand.warn.opacity(0.6) : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func detail(_ p: LabParameter) -> some View {
        let l = p.latest
        let points = p.results.compactMap { r in r.value.map { (r, $0) } }
        return Card(title: p.name, icon: "chart.xyaxis.line") {
            if points.count > 0 {
                Chart {
                    if let lo = l.refMin, let hi = l.refMax {
                        RectangleMark(xStart: nil, xEnd: nil, yStart: .value("mín", lo), yEnd: .value("máx", hi)).foregroundStyle(Brand.accent.opacity(0.12))
                    } else if let hi = l.refMax {
                        RuleMark(y: .value("máx", hi)).foregroundStyle(Brand.warn.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    } else if let lo = l.refMin {
                        RuleMark(y: .value("mín", lo)).foregroundStyle(Brand.warn.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                    ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("Día", p.0.date), y: .value(l.unit, p.1)).foregroundStyle(.secondary.opacity(0.6))
                        PointMark(x: .value("Día", p.0.date), y: .value(l.unit, p.1)).foregroundStyle(p.0.status.color).symbolSize(70)
                            .annotation(position: .top) { Text(MD.formatNumber(p.1, comma: true)).font(.caption2) }
                    }
                }
                .chartYAxisLabel(l.unit)
                .chartXScale(range: .plotDimension(padding: 20))
                .frame(height: 190)
            }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                GridRow { Text("Fecha"); Text("Resultado"); Text("Referencia"); Text("Estado"); Text("Notas"); Text("") }.font(.caption).foregroundStyle(.secondary)
                Divider()
                ForEach(p.results.reversed()) { r in
                    GridRow {
                        Text(DayKey.dmy(r.date)).monospacedDigit()
                        Text(r.valueText).monospacedDigit()
                        Text(r.refText.isEmpty ? "–" : r.refText).foregroundStyle(.secondary)
                        pill(r.status)
                        Text(r.note).foregroundStyle(.secondary).lineLimit(1)
                        EditButton { spec = RowSpec(file: Labs.file, mode: .edit(line: r.line), title: "resultado") }
                    }
                }
            }
        }
    }

    private func newForm(_ params: [LabParameter]) -> some View {
        let known = Array(Set(Labs.suggestedNames + params.map(\.name))).sorted { MD.fold($0) < MD.fold($1) }
        return Card(title: "Nueva analítica", icon: "plus.circle") {
            DatePicker("Fecha de la analítica", selection: $date, in: ...Date(), displayedComponents: .date).frame(width: 300)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow { Text("Parámetro"); Text("Resultado"); Text("Unidad"); Text("Ref. mín"); Text("Ref. máx"); Text("Estado"); Text("") }.font(.caption).foregroundStyle(.secondary)
                ForEach($rows) { $r in
                    GridRow {
                        HStack(spacing: 2) {
                            TextField("Glucosa", text: $r.name).frame(width: 150)
                            Menu {
                                ForEach(known, id: \.self) { n in Button(n) { r.name = n; fill(&r, from: params) } }
                            } label: { Image(systemName: "chevron.down.circle").accessibilityLabel("Elegir de la lista") }.menuStyle(.borderlessButton).fixedSize().help("Elegir de la lista")
                        }
                        TextField("", text: $r.value).frame(width: 80)
                        TextField("", text: $r.unit).frame(width: 70)
                        TextField("", text: $r.refMin).frame(width: 60)
                        TextField("", text: $r.refMax).frame(width: 60)
                        ChoiceMenu(options: ["", "bajo", "normal", "alto"], current: r.estado, width: 90) { r.estado = $0 }
                        Button { rows.removeAll { $0.id == r.id }; if rows.isEmpty { rows = [LabRowInput()] } } label: { Image(systemName: "minus.circle").accessibilityLabel("Quitar") }.buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Button { rows.append(LabRowInput()) } label: { Label("Otro parámetro", systemImage: "plus") }.controlSize(.small)
                Spacer()
                if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary) }
                Button("Guardar analítica") {
                    let n = rows.filter { !$0.name.isEmpty && !$0.value.isEmpty }.count
                    store.addLabResults(date: DayKey.calendar().startOfDay(for: date), rows: rows)
                    rows = [LabRowInput()]
                    message = "\(n) \(n == 1 ? "resultado guardado" : "resultados guardados")"
                }.buttonStyle(.borderedProminent).disabled(!rows.contains { !$0.name.isEmpty && !$0.value.isEmpty })
            }
            Text("Al elegir un parámetro de la lista se copian su unidad y su referencia de la última vez.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func fill(_ r: inout LabRowInput, from params: [LabParameter]) {
        guard let p = params.first(where: { $0.id == MD.fold(r.name) }) else { return }
        let l = p.latest
        r.unit = l.unit
        r.refMin = l.refMin.map { MD.formatNumber($0, comma: true) } ?? ""
        r.refMax = l.refMax.map { MD.formatNumber($0, comma: true) } ?? ""
    }
}
