import Charts
import SwiftUI

struct GastosView: View {
    @Environment(Store.self) private var store
    /// Meses respecto al actual (0 = este mes).
    @State private var offset = 0
    @State private var quick = ""
    /// Partida elegida a mano para el gasto que se está escribiendo; `nil` = la que se adivina.
    @State private var chosen: String?
    @State private var lastAdded = ""
    /// Partida cuyos movimientos se están viendo.
    @State private var filter: String?
    /// Ahorro mensual para la simulación del fondo; `nil` = lo previsto en la partida de ahorro.
    @State private var monthly: Double?
    @State private var addLeftover = false

    private var month: String {
        Budget.monthKey(DayKey.calendar().date(byAdding: .month, value: offset, to: DayKey.today()) ?? DayKey.today())
    }

    var body: some View {
        let m = month
        let budget = store.budget(m)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(m)
                quickAdd(budget ?? store.budgetMonths.last.flatMap { store.budget($0) })
                if let b = budget {
                    content(b, previous: store.budgets(before: m))
                } else {
                    Card(title: "Sin presupuesto para \(Budget.title(m).lowercased())", icon: "calendar.badge.plus") {
                        EmptyNote(store.budgetMonths.isEmpty
                                  ? "Se crea con las partidas de tu hoja de Numbers. Pon lo previsto de cada una y empieza a apuntar gastos."
                                  : "Se crea copiando ingresos, partidas y lo previsto del último mes.", icon: "eurosign.circle")
                        Button("Crear el presupuesto de \(Budget.title(m).lowercased())") { store.createBudget(m) }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Gastos")
    }

    // MARK: Cabecera y añadir

    private func header(_ m: String) -> some View {
        HStack(spacing: 10) {
            Button { offset -= 1 } label: { Image(systemName: "chevron.left").accessibilityLabel("Mes anterior") }
            Text(Budget.title(m)).font(.title.bold())
            Button { offset += 1 } label: { Image(systemName: "chevron.right").accessibilityLabel("Mes siguiente") }
            if offset != 0 { Button("Este mes") { offset = 0 }.buttonStyle(.accentLink) }
            Spacer()
            if store.budget(m) != nil { Button("Abrir nota") { store.pendingNote = store.budgetPath(m) }.buttonStyle(.accentLink) }
        }
        .buttonStyle(.borderless)
    }

    private func quickAdd(_ reference: Budget?) -> some View {
        let categories = reference?.lines.map(\.name) ?? Edit.defaultBudgetLines.map(\.0)
        let parsed = ExpenseParser.parse(quick, categories: categories, people: store.people.map(\.name))
        let category = chosen ?? parsed?.category
        return Card(title: "Añadir gasto", icon: "plus.circle",
                    info: "Escribe como hablas: «22 € cena con Ana», «gasolina 48», «ayer 12,50 pan». La partida se adivina por las palabras; si falla, elígela en el menú. Se apunta en la nota del mes de la fecha.") {
            HStack {
                TextField("22 € cena con Ana", text: $quick).textFieldStyle(.roundedBorder).onSubmit { add(parsed, category) }
                Button("Añadir") { add(parsed, category) }.buttonStyle(.borderedProminent).disabled(parsed == nil || category == nil)
            }
            if let p = parsed {
                FlowLayout(spacing: 6) {
                    chip(Money.format(p.amount).replacingOccurrences(of: ",00", with: ""), tint: Brand.accent)
                    ChoiceMenu(options: categories, current: category ?? "", width: 220, emptyLabel: "Elige partida") { chosen = $0 }
                    chip(DayKey.days(from: DayKey.today(), to: p.date) == 0 ? "hoy" : longDate(p.date), tint: .secondary)
                    if let person = p.person { chip("con \(person)", tint: Brand.info) }
                    if let c = category, let r = reference, Budget.monthKey(p.date) == r.month, let l = r.line(named: c) {
                        Text("\(c) pasaría a \(Money.format(r.real(l) + p.amount)) de \(Money.format(l.planned))")
                            .font(.caption).foregroundStyle(r.real(l) + p.amount > l.planned ? Brand.bad : .secondary)
                    }
                }
            } else if !lastAdded.isEmpty {
                Label(lastAdded, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(Brand.accent)
            }
        }
        .onChange(of: quick) { if quick.isEmpty { chosen = nil } }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text).font(.callout.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule()).foregroundStyle(tint == .secondary ? Color.primary : tint)
    }

    private func add(_ p: ExpenseParser.Result?, _ category: String?) {
        guard let p, let category else { return }
        store.addExpense(p.amount, category: category, note: p.note, date: p.date)
        lastAdded = "Apuntado: \(Money.format(p.amount)) en \(category)" + (p.note.isEmpty ? "" : " · \(p.note)")
        quick = ""
        chosen = nil
    }

    // MARK: Contenido

    @ViewBuilder private func content(_ b: Budget, previous: [Budget]) -> some View {
        let s = BudgetStatus(b)
        let insights = Budget.insights(b, previous: previous, status: s, events: s.isCurrent ? store.pendingContributions : [])
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            if s.isCurrent {
                Tile(title: "Puedes gastar hoy", value: Money.format(s.perDay), note: "\(Money.format(s.variableLeft)) en variables para \(s.daysLeft) días", tint: Brand.accent)
                Tile(title: "Sobrará el \(s.days)", value: Money.format(s.endLeft), note: "si sigues al ritmo de estos \(s.day) días", tint: s.endLeft < 0 ? Brand.bad : nil)
            } else {
                Tile(title: s.day == 0 ? "Previsto que sobre" : "Sobró", value: Money.format(s.day == 0 ? b.income - b.planned : b.income - b.spent - b.saved), tint: Brand.accent)
                Tile(title: "Ahorrado", value: Money.format(b.saved))
            }
            Tile(title: "Gastado", value: Money.format(b.spent), note: "de \(Money.format(b.plannedExpenses)) previstos · ingresos \(Money.format(b.income))")
            let fixed = b.lines.filter { $0.kind != .variable }
            let pending = fixed.filter { !$0.paid && b.real($0) == 0 }
            Tile(title: "Pagos fijos", value: "\(fixed.count - pending.count) de \(fixed.count)",
                 note: pending.isEmpty ? "todos pagados" : "\(Money.format(pending.reduce(0) { $0 + $1.planned })) por pagar")
        }
        if b.income == 0 || b.planned == 0 {
            Label("Pon lo previsto de ingresos y partidas (abajo) para ver el ritmo y las previsiones.", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
        }
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) { paceCard(b, s); remainingCard(b, s) }.frame(maxWidth: .infinity)
                VStack(spacing: 16) { insightsCard(insights); fundCard(b, s) }.frame(width: 360)
            }
            VStack(spacing: 16) { paceCard(b, s); insightsCard(insights); remainingCard(b, s); fundCard(b, s) }
        }
        incomeCard(b)
        linesCard(b, previous: previous)
        movesCard(b)
        historyCard(b, previous: store.budgets(before: b.month, limit: 5))
    }

    private func paceCard(_ b: Budget, _ s: BudgetStatus) -> some View {
        let variables = b.lines.filter { $0.kind == .variable && $0.planned > 0 }
        return Card(title: "Ritmo del mes", icon: "speedometer",
                    info: "La raya marca lo que tocaría llevar gastado hoy si se reparte lo previsto por igual entre los días del mes. La previsión supone que sigues al mismo ritmo.") {
            if variables.isEmpty { EmptyNote("Ninguna partida variable con algo previsto.", icon: "speedometer") }
            ForEach(variables) { l in
                let r = b.real(l), proj = s.projection[l.name] ?? r
                let over = r > l.planned, risk = s.isCurrent && proj > l.planned * 1.03
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Button(l.name) { filter = l.name }.buttonStyle(.plain).fontWeight(.medium)
                        Text("\(Money.format(r)) de \(Money.format(l.planned))").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        Spacer()
                        Text(over ? "pasado en \(Money.format(r - l.planned))" : !s.isCurrent ? "dentro" : risk ? "a este ritmo, ~\(Money.format(proj))" : "vas bien · ~\(Money.format(proj))")
                            .font(.callout.weight(.medium)).foregroundStyle(over ? Brand.bad : risk ? Brand.warn : Brand.accent)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(over ? Brand.bad : risk ? Brand.warn : Brand.accent).frame(width: g.size.width * min(1, r / l.planned))
                            if s.isCurrent {
                                RoundedRectangle(cornerRadius: 1).fill(Color.primary).frame(width: 2, height: 16).offset(x: g.size.width * s.fraction - 1)
                            }
                        }
                    }
                    .frame(height: 10)
                    .accessibilityElement().accessibilityLabel("\(l.name): \(Int(r / l.planned * 100)) % de lo previsto")
                }
            }
        }
    }

    private func remainingCard(_ b: Budget, _ s: BudgetStatus) -> some View {
        let series = s.remainingByDay(b)
        let low = series.forecast.min { $0.1 < $1.1 }
        return Card(title: "Lo que te queda del mes", icon: "chart.line.downtrend.xyaxis",
                    info: "Ingresos del mes menos lo gastado, día a día. Desde hoy, la línea discontinua suma los pagos fijos en su día y los variables al ritmo que llevas.") {
            Chart {
                ForEach(series.real, id: \.0) { d, v in
                    LineMark(x: .value("Día", d), y: .value("€", v), series: .value("s", "real")).foregroundStyle(Brand.accent).lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                ForEach(series.forecast, id: \.0) { d, v in
                    LineMark(x: .value("Día", d), y: .value("€", v), series: .value("s", "previsto")).foregroundStyle(Brand.info).lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
                RuleMark(y: .value("Cero", 0)).foregroundStyle(Brand.bad.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            .chartXScale(domain: 1...s.days)
            .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel() } }
            .frame(height: 170)
            .accessibilityLabel("Lo que queda del mes día a día")
            if let today = series.real.last {
                Text("Hoy quedan \(Money.format(today.1))." + (low.map { $0.1 < today.1 ? " Lo más bajo será ~\(Money.format($0.1)) el día \($0.0)." : "" } ?? ""))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func insightsCard(_ items: [BudgetInsight]) -> some View {
        Card(title: "Lo que conviene mirar", icon: "lightbulb") {
            if items.isEmpty { EmptyNote("Nada fuera de lo normal este mes.", icon: "checkmark.seal") }
            ForEach(items) { i in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(color(i.level)).frame(width: 8, height: 8).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(i.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                        if let c = i.category { Button("Ver movimientos de \(c)") { filter = c }.buttonStyle(.accentLink).font(.caption) }
                        if let p = i.notePath { Button("Abrir nota") { store.pendingNote = p }.buttonStyle(.accentLink).font(.caption) }
                    }
                }
            }
        }
    }

    private func color(_ l: BudgetInsight.Level) -> Color {
        switch l { case .info: Brand.info; case .warn: Brand.warn; case .bad: Brand.bad; case .good: Brand.accent }
    }

    private func fundCard(_ b: Budget, _ s: BudgetStatus) -> some View {
        let now = Money.parse(store.noteMeta[VaultPath.finanzas]?["fondo_emergencia_eur"] ?? "")
        let goal = b.plannedExpenses * 3
        let planned = b.lines.filter { $0.kind == .ahorro }.reduce(0) { $0 + $1.planned }
        let perMonth = monthly ?? (planned > 0 ? planned : 300)
        let extra = addLeftover && s.isCurrent ? max(0, s.endLeft) : 0
        let months = perMonth > 0 ? Int(((goal - now - extra) / perMonth).rounded(.up)) : 0
        let reach = DayKey.calendar().date(byAdding: .month, value: max(months, 0), to: Budget.firstDay(b.month) ?? DayKey.today()) ?? DayKey.today()
        return Card(title: "Fondo de emergencia", icon: "shield.lefthalf.filled",
                    info: "La meta son 3 meses de tus gastos previstos (sin el ahorro). Lo que tienes se guarda en la propiedad fondo_emergencia_eur de la nota Finanzas.") {
            HStack {
                Text("Tienes").foregroundStyle(.secondary)
                PropertyField(file: VaultPath.finanzas, key: "fondo_emergencia_eur", width: 90)
                Text("€ de \(Money.format(goal))").foregroundStyle(.secondary)
            }
            MiniBar(value: goal > 0 ? now / goal : 0, color: Brand.sky)
            HStack {
                Text("Ahorro al mes")
                Spacer()
                Text(Money.format(perMonth)).monospacedDigit().fontWeight(.semibold)
            }.font(.callout)
            Slider(value: Binding(get: { perMonth }, set: { monthly = $0 }), in: 50...1000, step: 25).tint(Brand.accent)
            if s.isCurrent, s.endLeft > 0 { Toggle("Sumar lo que sobre este mes (~\(Money.format(s.endLeft)))", isOn: $addLeftover).toggleStyle(.checkbox).font(.callout) }
            Text(goal <= 0 ? "Pon lo previsto de las partidas para calcular la meta." : now + extra >= goal ? "Ya tienes los 3 meses cubiertos." : "Llegarías en \(DayKey.esLong(reach, .dateTime.month(.wide).year())) · \(months) \(months == 1 ? "mes" : "meses") ahorrando \(Money.format(perMonth)).")
                .font(.callout).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.sky.opacity(0.12), in: RoundedRectangle(cornerRadius: Brand.radius))
        }
    }

    private func incomeCard(_ b: Budget) -> some View {
        Card(title: "Ingresos", icon: "arrow.down.circle", info: "Si «Real» está vacío se cuenta lo previsto.") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow { Text("Concepto"); Text("Previsto"); Text("Real") }.font(.caption).foregroundStyle(.secondary)
                ForEach(b.incomes) { i in
                    GridRow {
                        Text(i.name)
                        AmountCell(value: i.planned) { store.setBudgetCell(b, section: "Ingresos", line: i.line, name: i.name, column: "Previsto", value: $0) }
                        AmountCell(value: i.real) { store.setBudgetCell(b, section: "Ingresos", line: i.line, name: i.name, column: "Real", value: $0) }
                    }
                }
            }
        }
    }

    private func linesCard(_ b: Budget, previous: [Budget]) -> some View {
        Card(title: "Partidas", icon: "list.bullet.rectangle",
             info: "«Real» es la suma de los movimientos de cada partida; si no tiene y está marcada como pagada, cuenta lo previsto. «Vs media» compara con los meses anteriores. Edita lo previsto y pulsa intro.") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                GridRow {
                    Text(""); Text("Partida"); Text(""); Text("Previsto"); Text("Real"); Text("Tipo"); Text("Vs media")
                }.font(.caption).foregroundStyle(.secondary)
                ForEach(b.lines) { l in
                    let r = b.real(l)
                    let past = previous.compactMap { p in p.line(named: l.name).map { p.real($0) } }.filter { $0 > 0 }
                    let avg = past.isEmpty ? nil : past.reduce(0, +) / Double(past.count)
                    GridRow {
                        if l.kind == .variable { Color.clear.frame(width: 18, height: 18) } else {
                            Button {
                                store.setBudgetCell(b, section: "Partidas", line: l.line, name: l.name, column: "Pagado", value: l.paid ? "" : "✅")
                            } label: { Image(systemName: l.paid ? "checkmark.circle.fill" : "circle").foregroundStyle(l.paid ? Brand.good : .secondary) }
                                .buttonStyle(.plain).accessibilityLabel(l.paid ? "Marcar sin pagar" : "Marcar pagado")
                        }
                        HStack(spacing: 6) {
                            Button(l.name) { filter = l.name }.buttonStyle(.plain).lineLimit(1)
                            if let d = l.day { Text("día \(d)").font(.caption).foregroundStyle(.secondary) }
                        }
                        MiniBar(value: l.planned > 0 ? r / l.planned : 0, color: r > l.planned ? Brand.bad : l.kind == .ahorro ? Brand.sky : Brand.accent).frame(width: 110)
                        AmountCell(value: l.planned) { store.setBudgetCell(b, section: "Partidas", line: l.line, name: l.name, column: "Previsto", value: $0) }
                        Text(r == 0 ? "–" : Money.format(r)).monospacedDigit().fontWeight(.medium).foregroundStyle(r > l.planned ? Brand.bad : r == 0 ? .secondary : .primary)
                        ChoiceMenu(options: BudgetLine.Kind.allCases.map(\.rawValue), current: l.kind.rawValue, width: 96) {
                            store.setBudgetCell(b, section: "Partidas", line: l.line, name: l.name, column: "Tipo", value: $0)
                        }
                        Text(trend(r, avg)).font(.caption).monospacedDigit().foregroundStyle(avg.map { r >= $0 * 1.1 && r > 0 } ?? false ? Brand.bad : .secondary)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text(""); Text("Total").fontWeight(.semibold); Text("")
                    Text(Money.format(b.planned)).monospacedDigit().fontWeight(.semibold)
                    Text(Money.format(b.spent + b.saved)).monospacedDigit().fontWeight(.semibold)
                }
            }
            if b.unassigned > 0 {
                Label("\(Money.format(b.unassigned)) en movimientos con una partida que no está en la tabla.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Brand.warn)
            }
        }
    }

    private func trend(_ r: Double, _ avg: Double?) -> String {
        guard let avg, avg > 0, r > 0 else { return "" }
        let d = Int(((r - avg) / avg * 100).rounded())
        return abs(d) < 3 ? "=" : (d > 0 ? "+\(d) %" : "−\(-d) %")
    }

    private func movesCard(_ b: Budget) -> some View {
        let all = b.moves.sorted { ($0.date, $0.line) > ($1.date, $1.line) }
        let shown = filter.map { f in all.filter { MD.fold($0.category) == MD.fold(f) } } ?? all
        return Card(title: filter.map { "Movimientos · \($0)" } ?? "Movimientos", icon: "list.dash", actionTitle: filter == nil ? nil : "Ver todos", action: { filter = nil }) {
            if shown.isEmpty { EmptyNote(filter == nil ? "Aún no hay gastos apuntados este mes." : "Ningún gasto en esta partida.", icon: "tray") }
            ForEach(shown.prefix(40)) { m in MoveRow(budget: b, move: m) }
            if shown.count > 40 { Text("y \(shown.count - 40) más en la nota del mes").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func historyCard(_ b: Budget, previous: [Budget]) -> some View {
        let months = (previous.reversed() + [b])
        return Card(title: "Últimos meses", icon: "chart.bar") {
            if months.count < 2 { EmptyNote("Con dos meses apuntados verás aquí cómo cambia el gasto.", icon: "chart.bar") }
            else {
                Chart {
                    ForEach(months, id: \.month) { m in
                        let label = DayKey.esLong(Budget.firstDay(m.month) ?? Date(), .dateTime.month(.abbreviated))
                        BarMark(x: .value("Mes", label), y: .value("€", m.spent)).foregroundStyle(by: .value("Tipo", "Gastado"))
                        BarMark(x: .value("Mes", label), y: .value("€", m.saved)).foregroundStyle(by: .value("Tipo", "Ahorrado"))
                    }
                }
                .chartForegroundStyleScale(["Gastado": Brand.accent, "Ahorrado": Brand.info])
                .frame(height: 160)
                let avg = previous.isEmpty ? 0 : previous.reduce(0) { $0 + $1.spent } / Double(previous.count)
                Text("Media de gasto de los meses anteriores: \(Money.format(avg)).").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Barra de progreso con el color que se le da (la de sistema lo pierde en ventanas inactivas).
private struct MiniBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color).frame(width: g.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 8)
    }
}

/// Importe editable en una celda de la nota del mes: se guarda al pulsar intro.
private struct AmountCell: View {
    let value: Double?
    let save: (String) -> Void
    @State private var text = ""

    private var current: String { value.map(Edit.budgetNumber) ?? "" }

    var body: some View {
        TextField("–", text: $text).multilineTextAlignment(.trailing).monospacedDigit().frame(width: 80)
            .onSubmit { if text != current { save(text.isEmpty ? "" : Edit.budgetNumber(Money.parse(text))) } }
            .onAppear { text = current }
            .onChange(of: value) { text = current }
    }
}

private struct MoveRow: View {
    @Environment(Store.self) private var store
    let budget: Budget
    let move: BudgetMove
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Text(DayKey.esLong(move.date, .dateTime.day().month(.abbreviated))).font(.callout).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
            Text(move.category).font(.callout).lineLimit(1).frame(width: 190, alignment: .leading)
            Text(MDParser.inline(move.note)).font(.callout).lineLimit(1)
            Spacer()
            Text(Money.format(move.amount)).monospacedDigit().fontWeight(.medium)
            Button { store.deleteExpense(budget, move) } label: { Image(systemName: "trash").accessibilityLabel("Borrar gasto") }
                .buttonStyle(.borderless).opacity(hover ? 1 : 0)
        }
        .onHover { hover = $0 }
    }
}
