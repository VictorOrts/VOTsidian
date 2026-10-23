import Charts
import SwiftUI

/// Resumen de un año de Gastos: por mes, lo que entró, lo que se gastó y lo que quedó. Los datos salen de las notas
/// de cada mes; «Guardar en nota» deja la misma tabla en `Finanzas/Gastos/Resumen AAAA.md`.
struct GastosYearView: View {
    @Environment(Store.self) private var store
    let year: Int
    /// Abre un mes (`AAAA-MM`) en la vista de mes.
    let open: (String) -> Void
    /// Mes bajo el ratón en la gráfica (abreviatura, «oct»).
    @State private var hovered: String?

    private static let abbr = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
    private static func label(_ m: BudgetYear.Month) -> String { abbr[max(0, min(11, m.number - 1))] }

    var body: some View {
        let y = store.budgetYear(year)
        if y.months.isEmpty {
            Card(title: "Sin gastos de \(String(year))", icon: "calendar") {
                EmptyNote(store.budgetYears.isEmpty ? "Aún no hay ninguna nota de mes en Gastos." : "Hay notas de: \(store.budgetYears.map(String.init).joined(separator: ", ")).", icon: "eurosign.circle")
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                Tile(title: "Ingresos", value: Money.format(y.income), note: "\(y.months.count) \(y.months.count == 1 ? "mes" : "meses") con nota")
                Tile(title: "Gastos", value: Money.format(y.spent), note: "sin contar el ahorro")
                Tile(title: "Queda", value: Money.format(y.left), note: "ingresos − gastos", tint: y.left < 0 ? Brand.bad : Brand.accent)
            }
            chartCard(y)
            tableCard(y)
        }
    }

    private func chartCard(_ y: BudgetYear) -> some View {
        let shown = y.months.first { Self.label($0) == hovered }
        return Card(title: "Ingresos y gastos", icon: "chart.bar",
                    info: "Lo que entró y lo que se gastó cada mes (sin el ahorro). Pasa el ratón por un mes para ver lo que quedó.") {
            Chart {
                ForEach(y.months) { m in
                    // El mes en curso va más claro: aún no ha acabado.
                    let alpha = m.month == y.current ? 0.5 : 1.0
                    BarMark(x: .value("Mes", Self.label(m)), y: .value("€", m.income), width: .ratio(0.8))
                        .foregroundStyle(by: .value("Tipo", "Ingresos")).position(by: .value("Tipo", "Ingresos")).opacity(alpha)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                    BarMark(x: .value("Mes", Self.label(m)), y: .value("€", m.spent), width: .ratio(0.8))
                        .foregroundStyle(by: .value("Tipo", "Gastos")).position(by: .value("Tipo", "Gastos")).opacity(alpha)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                }
                if let h = hovered, let s = shown {
                    RuleMark(x: .value("Mes", h)).foregroundStyle(Color.primary.opacity(0.08)).lineStyle(StrokeStyle(lineWidth: 40))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) { tooltip(s) }
                }
            }
            .chartForegroundStyleScale(["Ingresos": Brand.info, "Gastos": Brand.amber])
            .chartXScale(domain: Self.abbr)
            .chartXSelection(value: $hovered)
            .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel { if let d = v.as(Double.self) { Text(Money.format(d)) } } } }
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 230)
            .accessibilityLabel("Ingresos y gastos de cada mes de \(String(y.year))")
            if let c = y.current { Text("\(Budget.title(c)) aún no ha acabado: va más claro.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func tooltip(_ m: BudgetYear.Month) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Budget.title(m.month)).font(.caption.weight(.semibold))
            ForEach([("Ingresos", m.income), ("Gastos", m.spent), ("Queda", m.left)], id: \.0) { name, v in
                HStack { Text(name).foregroundStyle(.secondary); Spacer(minLength: 12); Text(Money.format(v)).monospacedDigit() }.font(.caption)
            }
        }
        .padding(8).frame(width: 160)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Brand.radiusSmall))
    }

    private func tableCard(_ y: BudgetYear) -> some View {
        let path = store.yearSummaryPath(y.year)
        let exists = store.noteTexts[path] != nil
        return Card(title: "Mes a mes", icon: "tablecells",
                    info: "Cada fila sale de la nota de ese mes; pulsa el mes para abrirlo. «Guardar en nota» deja esta tabla en \(path) (se rehace entera al actualizar y se deshace con ⌥⌘Z).") {
            Grid(alignment: .trailing, horizontalSpacing: 28, verticalSpacing: 6) {
                GridRow { Text("Mes").gridColumnAlignment(.leading); Text("Ingresos"); Text("Gastos"); Text("Queda") }.font(.caption).foregroundStyle(.secondary)
                ForEach(y.months) { m in
                    GridRow {
                        Button(Budget.title(m.month) + (m.month == y.current ? " · en curso" : "")) { open(m.month) }.buttonStyle(.accentLink)
                        amount(m.income); amount(m.spent)
                        amount(m.left).fontWeight(.medium).foregroundStyle(m.left < 0 ? Brand.bad : .primary)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text("Total").fontWeight(.semibold)
                    amount(y.income); amount(y.spent); amount(y.left).fontWeight(.semibold).foregroundStyle(y.left < 0 ? Brand.bad : .primary)
                }
            }
            .font(.callout)
            Divider()
            HStack {
                Button(exists ? "Actualizar nota" : "Guardar en nota") { store.writeYearSummary(y.year) }.buttonStyle(.borderedProminent)
                if exists { Button("Abrir nota") { store.pendingNote = path }.buttonStyle(.accentLink) }
                Spacer()
            }
        }
    }

    private func amount(_ v: Double) -> Text { Text(Money.format(v)).monospacedDigit() }
}
