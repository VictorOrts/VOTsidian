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
    /// `true` = todas las partidas en «Por partida»; si no, las principales.
    @State private var showAll = false

    private static let topCategories = 8

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
                Tile(title: "Ingresos", value: Money.format(y.income), note: "\(y.months.count) \(y.months.count == 1 ? "mes" : "meses") con nota" + (y.future.isEmpty ? "" : " · \(y.future.count) previsto\(y.future.count == 1 ? "" : "s")"))
                Tile(title: "Gastos", value: Money.format(y.spent), note: y.averageSpent.map { "media de los meses acabados: \(Money.format($0))" } ?? "sin contar el ahorro")
                Tile(title: "Queda", value: Money.format(y.left), note: queda(y), tint: y.left < 0 ? Brand.bad : Brand.accent)
                if let c = y.spentChange(from: store.budgetYear(year - 1)) {
                    let pct = Int(((c.now / c.before - 1) * 100).rounded())
                    Tile(title: "Gastos frente a \(String(year - 1))", value: pct == 0 ? "=" : (pct > 0 ? "+\(pct) %" : "−\(-pct) %"),
                         note: "\(Self.span(c.months)): \(Money.format(c.before)) → \(Money.format(c.now))",
                         tint: pct > 2 ? Brand.warn : pct < -2 ? Brand.accent : nil)
                }
            }
            chartCard(y)
            tableCard(y)
            categoriesCard(y)
        }
    }

    private func queda(_ y: BudgetYear) -> String {
        let rate = y.savingsRate.map { "\(Money.percent($0)) de lo que entró" } ?? "ingresos − gastos"
        return y.saved > 0 ? "\(rate) · \(Money.format(y.saved)) apartados" : rate
    }

    /// Meses de la comparación: «ene–sep» si van seguidos; si no, cuántos son.
    private static func span(_ numbers: [Int]) -> String {
        guard let a = numbers.first, let b = numbers.last, (1...12).contains(a), (1...12).contains(b) else { return "" }
        guard numbers == Array(a...b) else { return "\(numbers.count) meses" }
        return a == b ? abbr[a - 1] : "\(abbr[a - 1])–\(abbr[b - 1])"
    }

    private func chartCard(_ y: BudgetYear) -> some View {
        let shown = y.months.first { Self.label($0) == hovered }
        return Card(title: "Ingresos y gastos", icon: "chart.bar",
                    info: "Lo que entró y lo que se gastó cada mes (sin el ahorro). La línea discontinua es el gasto medio de los meses acabados. Pasa el ratón por un mes para ver lo que quedó.") {
            Chart {
                ForEach(y.months) { m in
                    // El mes en curso va más claro (aún no ha acabado) y uno por venir, más aún (es previsión).
                    let alpha = m.planned ? 0.25 : m.month == y.current ? 0.5 : 1.0
                    BarMark(x: .value("Mes", Self.label(m)), y: .value("€", m.income), width: .ratio(0.8))
                        .foregroundStyle(by: .value("Tipo", "Ingresos")).position(by: .value("Tipo", "Ingresos")).opacity(alpha)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                    BarMark(x: .value("Mes", Self.label(m)), y: .value("€", m.spent), width: .ratio(0.8))
                        .foregroundStyle(by: .value("Tipo", "Gastos")).position(by: .value("Tipo", "Gastos")).opacity(alpha)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                }
                if let avg = y.averageSpent {
                    RuleMark(y: .value("Media", avg))
                        .foregroundStyle(Brand.amber.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing, spacing: 2) {
                            Text("media \(Money.format(avg))").font(.caption2).foregroundStyle(.secondary)
                        }
                }
                if let h = hovered, let s = shown {
                    RectangleMark(x: .value("Mes", h), width: .ratio(1)).foregroundStyle(Color.primary.opacity(0.06))
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
            if !y.future.isEmpty {
                Text("\(y.future.map { Budget.title($0) }.joined(separator: ", ")) aún no \(y.future.count == 1 ? "ha" : "han") empezado: \(y.future.count == 1 ? "sale" : "salen") con lo previsto de cada partida (o lo ya pagado, si es más).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func tooltip(_ m: BudgetYear.Month) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Budget.title(m.month) + (m.planned ? " · previsto" : "")).font(.caption.weight(.semibold))
            ForEach([("Ingresos", Money.format(m.income)), ("Gastos", Money.format(m.spent)), ("Queda", Money.format(m.left))]
                    + (m.savingsRate.map { [("% ahorro", Money.percent($0))] } ?? [])
                    + (m.saved > 0 ? [("Apartado", Money.format(m.saved))] : []), id: \.0) { name, v in
                HStack { Text(name).foregroundStyle(.secondary); Spacer(minLength: 12); Text(v).monospacedDigit() }.font(.caption)
            }
        }
        .padding(8).frame(width: 170)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Brand.radiusSmall))
    }

    private func tableCard(_ y: BudgetYear) -> some View {
        let path = store.yearSummaryPath(y.year)
        let upToDate = store.yearSummaryIsCurrent(y.year)
        let exists = upToDate != nil
        return Card(title: "Mes a mes", icon: "tablecells",
                    info: "Cada fila sale de la nota de ese mes; pulsa el mes para abrirlo. «Guardar en nota» deja esta tabla en \(path). Al actualizarla se rehace la tabla y se conserva lo que escribas en «Comentarios»; se deshace con ⌥⌘Z.") {
            Grid(alignment: .trailing, horizontalSpacing: 28, verticalSpacing: 6) {
                GridRow { Text("Mes").gridColumnAlignment(.leading); Text("Ingresos"); Text("Gastos"); Text("Queda"); Text("% ahorro") }.font(.caption).foregroundStyle(.secondary)
                ForEach(y.months) { m in
                    GridRow {
                        Button(Budget.title(m.month) + (m.month == y.current ? " · en curso" : m.planned ? " · previsto" : "")) { open(m.month) }.buttonStyle(.accentLink)
                        amount(m.income); amount(m.spent)
                        amount(m.left).fontWeight(.medium).foregroundStyle(m.left < 0 ? Brand.bad : .primary)
                        rate(m.savingsRate)
                    }
                    .foregroundStyle(m.planned ? .secondary : .primary)
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text("Total").fontWeight(.semibold)
                    amount(y.income); amount(y.spent); amount(y.left).fontWeight(.semibold).foregroundStyle(y.left < 0 ? Brand.bad : .primary)
                    rate(y.savingsRate).fontWeight(.semibold)
                }
            }
            .font(.callout)
            Divider()
            HStack {
                if upToDate == true {
                    Label("La nota está al día", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(Brand.good)
                } else {
                    Button(exists ? "Actualizar nota" : "Guardar en nota") { store.writeYearSummary(y.year) }.buttonStyle(.borderedProminent)
                    if exists { Text("La nota no tiene las cifras de ahora.").font(.caption).foregroundStyle(Brand.warn) }
                }
                if exists { Button("Abrir nota") { store.pendingNote = path }.buttonStyle(.accentLink) }
                Spacer()
            }
        }
    }

    private func categoriesCard(_ y: BudgetYear) -> some View {
        let all = y.expenseCategories.filter { $0.spent != 0 || $0.planned != 0 }
        let shown = showAll ? all : Array(all.prefix(Self.topCategories))
        let top = max(all.first?.spent ?? 0, 1)
        return Card(title: "Por partida", icon: "list.bullet.rectangle",
                    info: "Cada partida sumada en todos los meses con nota. «Previsto» suma lo previsto de cada mes (el mes en curso, entero); «Gastado», lo apuntado (en los meses previstos, lo previsto o lo ya pagado). Las de ahorro no cuentan como gasto.") {
            if all.isEmpty {
                EmptyNote("Aún no hay gastos apuntados este año.", icon: "eurosign.circle")
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text("Partida").gridColumnAlignment(.leading); Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Text("Previsto"); Text("Gastado"); Text("Diferencia"); Text("% del gasto")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    ForEach(shown) { c in
                        GridRow {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.name).lineLimit(1)
                                Text(c.kind?.rawValue ?? "Sin partida en la tabla").font(.caption2).foregroundStyle(.secondary)
                            }
                            MiniBar(value: c.spent / top, color: Brand.amber.opacity(0.85)).frame(minWidth: 60, maxWidth: 140)
                            (c.planned == 0 ? Text("–") : amount(c.planned)).foregroundStyle(.secondary)
                            amount(c.spent)
                            difference(c)
                            rate(y.spent > 0 ? c.spent / y.spent : nil).foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.callout)
                HStack {
                    if all.count > Self.topCategories {
                        Button(showAll ? "Ver solo las \(Self.topCategories) principales" : "Ver las \(all.count) partidas") { showAll.toggle() }.buttonStyle(.accentLink)
                    }
                    Spacer()
                    if y.saved > 0 { Text("Apartado en ahorro: \(Money.format(y.saved))").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }

    /// Diferencia con lo previsto: en rojo si se pasa más de un 5 %, en verde si se queda por debajo. Sin previsto no hay con qué comparar.
    private func difference(_ c: BudgetYear.Category) -> some View {
        let over = c.difference > max(c.planned * 0.05, 0.5), under = c.difference < -0.5
        return Text(c.planned == 0 ? "–" : Money.signed(c.difference)).monospacedDigit()
            .foregroundStyle(c.planned == 0 ? .secondary : over ? Brand.bad : under ? Brand.good : .secondary)
    }

    private func amount(_ v: Double) -> Text { Text(Money.format(v)).monospacedDigit() }
    private func rate(_ r: Double?) -> Text { Text(r.map(Money.percent) ?? "–").monospacedDigit() }
}
