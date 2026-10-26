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
    @State private var newLine = ""
    @State private var newKind = BudgetLine.Kind.fijo
    @State private var newEvery = 1
    @State private var renaming: BudgetLine?
    @State private var renameText = ""
    @State private var search = ""
    @State private var newIncome = ""
    /// `true` = resumen del año en vez del mes. No se recuerda al salir: los avisos y el Inicio traen aquí para ver el mes.
    @State private var yearMode = false
    /// Año del resumen; `nil` = el del mes que se está viendo.
    @State private var year: Int?

    private var month: String {
        Budget.monthKey(DayKey.calendar().date(byAdding: .month, value: offset, to: DayKey.today()) ?? DayKey.today())
    }

    var body: some View {
        let _ = BodyCounter.hit("GastosView")
        let m = month
        let budget = store.budget(m)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if yearMode {
                    let y = year ?? Int(m.prefix(4)) ?? DayKey.calendar().component(.year, from: DayKey.today())
                    yearHeader(y)
                    // Clic en un mes del resumen: se abre ese mes.
                    GastosYearView(year: y, open: show)
                } else {
                    header(m)
                    quickAdd(budget ?? store.budgetMonths.last.flatMap { store.budget($0) })
                    if let b = budget {
                        content(b, previous: store.budgets(before: m))
                    } else {
                        Card(title: "Sin presupuesto para \(Budget.title(m).lowercased())", icon: "calendar.badge.plus") {
                            EmptyNote(store.budgetMonths.isEmpty
                                      ? "Se crea con las partidas de tu hoja de Numbers. Pon lo previsto de cada una y empieza a apuntar gastos."
                                      : "Se crea copiando ingresos, partidas y lo previsto del último mes.", icon: "eurosign.circle")
                                HStack {
                                Button("Crear el presupuesto de \(Budget.title(m).lowercased())") { store.createBudget(m) }.buttonStyle(.borderedProminent)
                                if let near = store.nearestBudgetMonth(to: m) {
                                    Button("Ver \(Budget.title(near).lowercased())") { show(near) }.buttonStyle(.accentLink)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Gastos")
        .onAppear(perform: consumePendingMonth)
        .onChange(of: store.pendingGastosMonth) { consumePendingMonth() }
        .onChange(of: store.pendingGastosYear) { consumePendingMonth() }
    }

    /// Enseña un mes (AAAA-MM) en la vista de mes.
    private func show(_ month: String) {
        offset = (BudgetLine.monthIndex(month) ?? 0) - (BudgetLine.monthIndex(Budget.monthKey(DayKey.today())) ?? 0)
        yearMode = false
    }

    private func consumePendingMonth() {
        if let y = store.pendingGastosYear { year = y; yearMode = true; store.pendingGastosYear = nil }
        guard let m = store.pendingGastosMonth else { return }
        show(m)
        store.pendingGastosMonth = nil
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
            modePicker
        }
        .buttonStyle(.borderless)
    }

    private func yearHeader(_ y: Int) -> some View {
        HStack(spacing: 10) {
            // Las flechas no llevan a años sin notas (salvo volver al año en curso).
            let thisYear = DayKey.calendar().component(.year, from: DayKey.today())
            Button { year = y - 1 } label: { Image(systemName: "chevron.left").accessibilityLabel("Año anterior") }
                .disabled(!store.budgetYears.contains { $0 < y } && y <= thisYear)
            Text("Resumen \(String(y))").font(.title.bold())
            Button { year = y + 1 } label: { Image(systemName: "chevron.right").accessibilityLabel("Año siguiente") }
                .disabled(!store.budgetYears.contains { $0 > y } && y >= thisYear)
            if y != thisYear { Button("Este año") { year = thisYear }.buttonStyle(.accentLink) }
            Spacer()
            modePicker
        }
        .buttonStyle(.borderless)
    }

    private var modePicker: some View {
        Picker("", selection: Binding(get: { yearMode }, set: { yearMode = $0; year = nil })) {
            Text("Mes").tag(false)
            Text("Año").tag(true)
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
    }

    private func quickAdd(_ reference: Budget?) -> some View {
        let categories = reference?.lines.map(\.name) ?? Edit.defaultBudgetLines.map(\.0)
        let parsed = ExpenseParser.parse(quick, categories: categories, people: store.people.map(\.name), learned: store.expenseLearned)
        let category = chosen ?? parsed?.category
        return Card(title: "Añadir gasto", icon: "plus.circle",
                    info: "Escribe como hablas: «22 € cena con Ana», «gasolina 48», «ayer 12,50 pan», «devolución 30 Zara». La partida se adivina por las palabras; si falla, elígela en el menú y la próxima vez acertará. Se apunta en la nota del mes de la fecha. Doble clic en un movimiento para corregirlo.") {
            HStack {
                TextField("22 € cena con Ana", text: $quick).textFieldStyle(.roundedBorder).onSubmit { add(parsed, category) }
                Button("Añadir") { add(parsed, category) }.buttonStyle(.borderedProminent).disabled(parsed == nil || category == nil)
            }
            if let p = parsed {
                FlowLayout(spacing: 6) {
                    chip(p.amount < 0 ? "devolución \(Money.exact(-p.amount))" : Money.exact(p.amount), tint: p.amount < 0 ? Brand.good : Brand.accent)
                    ChoiceMenu(options: categories, current: category ?? "", width: 220, emptyLabel: "Elige partida") { chosen = $0 }
                    chip(DayKey.days(from: DayKey.today(), to: p.date) == 0 ? "hoy" : longDate(p.date), tint: .secondary)
                    if let person = p.person { chip("con \(person)", tint: Brand.info) }
                    if let c = category, let r = reference, Budget.monthKey(p.date) == r.month, let l = r.line(named: c) {
                        Text("\(c) pasaría a \(Money.exact(r.real(l) + p.amount)) de \(Money.format(l.planned))")
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
        // Si corregiste la partida adivinada, se recuerda para la próxima vez («dentista» → Imprevistos).
        if let c = chosen, c != p.category { store.learnExpense(note: p.note, category: c) }
        store.addExpense(p.amount, category: category, note: p.note, date: p.date)
        // Si va a otro mes que el que estás viendo, se dice: si no, parece que no se apuntó.
        let elsewhere = Budget.monthKey(p.date) != month ? " · en \(Budget.title(Budget.monthKey(p.date)).lowercased())" : ""
        lastAdded = (p.amount < 0 ? "Devolución apuntada: \(Money.exact(-p.amount))" : "Apuntado: \(Money.exact(p.amount))") + " en \(category)" + (p.note.isEmpty ? "" : " · \(p.note)") + elsewhere
        quick = ""
        chosen = nil
    }

    // MARK: Contenido

    @ViewBuilder private func content(_ b: Budget, previous: [Budget]) -> some View {
        let s = BudgetStatus(b)
        // Al empezar el mes se está mirando el mes nuevo: el cierre del anterior (sobrante, pagos sin marcar) sale aquí también.
        let prevKey = BudgetLine.monthIndex(b.month).map { BudgetLine.month($0 - 1) }
        let closingPrevious = s.isCurrent && s.day <= 15 ? previous.first { $0.month == prevKey }.map(Budget.closing) ?? [] : []
        let insights = closingPrevious + Budget.insights(b, previous: previous, status: s, events: s.isCurrent ? store.pendingContributions : [])
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            if s.isCurrent {
                Tile(title: "Puedes gastar hoy", value: Money.format(s.leftToday),
                     note: s.spentToday > 0 ? "llevas \(Money.exact(s.spentToday)) de \(Money.format(s.todayAllowance)) · \(Money.format(s.variableLeft)) en \(s.daysLeft) \(s.daysLeft == 1 ? "día" : "días")"
                        : "\(Money.format(s.variableLeft)) para variables en \(s.daysLeft) \(s.daysLeft == 1 ? "día" : "días")",
                     tint: s.leftToday > 0 ? Brand.accent : Brand.bad)
                // Los dos primeros días la previsión es lo previsto, no el ritmo (ver BudgetStatus).
                Tile(title: "Sobrará el \(s.days)", value: Money.format(s.endLeft), note: s.day < 3 ? "según lo previsto" : "si sigues al ritmo de estos \(s.day) días", tint: s.endLeft < 0 ? Brand.bad : nil)
            } else {
                Tile(title: s.day == 0 ? "Previsto que sobre" : "Sobró", value: Money.format(s.day == 0 ? b.income - b.planned : b.income - b.spent - b.saved), tint: Brand.accent)
                Tile(title: "Ahorrado", value: Money.format(b.saved))
            }
            Tile(title: "Gastado", value: Money.format(b.spent), note: "de \(Money.format(b.plannedExpenses)) previstos · ingresos \(Money.format(b.income))")
            // Sin importe previsto no es un pago pendiente, es una partida por rellenar.
            let fixed = b.lines.filter { !$0.isDiscretionary && $0.isDue(b.month) && ($0.planned > 0 || b.real($0) > 0) }
            let pending = fixed.filter { !$0.paid && b.real($0) == 0 }
            Tile(title: "Pagos fijos", value: "\(fixed.count - pending.count) de \(fixed.count)",
                 note: pending.isEmpty ? "todos pagados" : "\(Money.format(pending.reduce(0) { $0 + $1.planned })) por pagar")
        }
        if b.income == 0 || b.planned == 0 {
            Label("Pon lo previsto de ingresos y partidas (abajo) para ver el ritmo y las previsiones.", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
        }
        // Sin variables con algo previsto «Ritmo del mes» no tiene nada que enseñar; en un mes por venir tampoco hay
        // «Lo que te queda». Sin ninguna de las dos, avisos y fondo van a la par en vez de junto a una caja vacía.
        let hasPace = b.lines.contains { $0.isDiscretionary && $0.planned > 0 }
        if !hasPace && s.day == 0 {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { insightsCard(insights); fundCard(b, s) }
                VStack(spacing: 16) { insightsCard(insights); fundCard(b, s) }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) { if hasPace { paceCard(b, s) }; if s.day > 0 { remainingCard(b, s) } }.frame(maxWidth: .infinity)
                    VStack(spacing: 16) { insightsCard(insights); fundCard(b, s) }.frame(width: 360)
                }
                VStack(spacing: 16) { if hasPace { paceCard(b, s) }; insightsCard(insights); if s.day > 0 { remainingCard(b, s) }; fundCard(b, s) }
            }
        }
        if b.lines.contains(where: { $0.every > 1 }) { reserveCard(b) }
        incomeCard(b)
        linesCard(b, previous: previous)
        movesCard(b)
        historyCard(b, previous: store.budgets(before: b.month, limit: 5))
    }

    private func paceCard(_ b: Budget, _ s: BudgetStatus) -> some View {
        let variables = b.lines.filter { $0.isDiscretionary && $0.planned > 0 }
        return Card(title: "Ritmo del mes", icon: "speedometer",
                    info: "La raya marca lo que tocaría llevar gastado hoy si se reparte lo previsto por igual entre los días del mes. La previsión supone que sigues al mismo ritmo.") {
            if variables.isEmpty { EmptyNote("Ninguna partida variable con algo previsto.", icon: "speedometer") }
            ForEach(variables) { l in
                let r = b.real(l), proj = s.projection[l.name] ?? r
                let over = r > l.planned, risk = s.isCurrent && proj > l.planned * 1.03
                let unknown = b.nothingLogged(s)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Button(l.name) { filter = l.name }.buttonStyle(.plain).fontWeight(.medium)
                        Text("\(Money.format(r)) de \(Money.format(l.planned))").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        Spacer()
                        Text(over ? "pasado en \(Money.format(r - l.planned))" : !s.isCurrent ? "dentro" : unknown ? "sin apuntar" : risk ? "a este ritmo, ~\(Money.format(proj))" : "vas bien · ~\(Money.format(proj))")
                            .font(.callout.weight(.medium)).foregroundStyle(over ? Brand.bad : risk ? Brand.warn : unknown ? .secondary : Brand.accent)
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
                    .accessibilityElement().accessibilityLabel("\(l.name): \(percentText(r / l.planned)) de lo previsto")
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
                        if let p = i.notePath {
                            HStack(spacing: 12) {
                                if let amount = i.pay {
                                    Button("Ya pagada: apuntar \(Money.exact(amount))") { store.payContribution(path: p, amount: amount) }.buttonStyle(.borderedProminent).controlSize(.small)
                                }
                                Button("Abrir nota") { store.pendingNote = p }.buttonStyle(.accentLink).font(.caption)
                            }
                        }
                        if let t = i.transfer, let b = store.budget(i.month ?? month) {
                            Button("Pasar \(Money.exact(t)) al fondo") { store.transferLeftover(b, amount: t) }.buttonStyle(.borderedProminent).controlSize(.small)
                        }
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
        let goal = b.typicalMonthExpenses * 3
        let planned = b.lines.filter { $0.kind == .ahorro }.reduce(0) { $0 + $1.planned }
        let perMonth = monthly ?? (planned > 0 ? planned : 300)
        let extra = addLeftover && s.isCurrent ? max(0, s.endLeft) : 0
        let months = perMonth > 0 ? Int(((goal - now - extra) / perMonth).rounded(.up)) : 0
        let reach = DayKey.calendar().date(byAdding: .month, value: max(months, 0), to: Budget.firstDay(b.month) ?? DayKey.today()) ?? DayKey.today()
        return Card(title: "Fondo de emergencia", icon: "shield.lefthalf.filled",
                    info: "La meta son 3 meses de tus gastos previstos (sin el ahorro; los cargos de cada varios meses cuentan su parte de cada mes). Lo que tienes se guarda en la propiedad fondo_emergencia_eur de la nota Finanzas.") {
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
            Slider(value: Binding(get: { perMonth }, set: { monthly = $0 }), in: 25...max(1000, (planned * 2).rounded(.up)), step: 25).tint(Brand.accent)
            if planned == 0, monthly == nil { Text("Sin ahorro previsto este mes: la simulación usa 300 €.").font(.caption).foregroundStyle(.secondary) }
            if s.isCurrent, s.endLeft > 0 { Toggle("Sumar lo que sobre este mes (~\(Money.format(s.endLeft)))", isOn: $addLeftover).toggleStyle(.checkbox).font(.callout) }
            Text(goal <= 0 ? "Pon lo previsto de las partidas para calcular la meta." : now + extra >= goal ? "Ya tienes los 3 meses cubiertos." : "Llegarías en \(DayKey.esLong(reach, .dateTime.month(.wide).year())) · \(months) \(months == 1 ? "mes" : "meses") ahorrando \(Money.format(perMonth)).")
                .font(.callout).fixedSize(horizontal: false, vertical: true).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.sky.opacity(0.12), in: RoundedRectangle(cornerRadius: Brand.radius))
        }
    }

    private func incomeCard(_ b: Budget) -> some View {
        Card(title: "Ingresos", icon: "arrow.down.circle", info: "Si «Real» está vacío se cuenta lo previsto. Clic derecho en un concepto para quitarlo; los meses nuevos copian los conceptos de este.") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow { Text("Concepto"); Text("Previsto"); Text("Real") }.font(.caption).foregroundStyle(.secondary)
                ForEach(b.incomes) { i in
                    GridRow {
                        Text(i.name).contextMenu { Button("Quitar «\(i.name)»", role: .destructive) { store.removeBudgetIncome(b, i) } }
                        AmountCell(value: i.planned) { store.setBudgetCell(b, section: "Ingresos", line: i.line, name: i.name, column: "Previsto", value: $0) }
                        AmountCell(value: i.real) { store.setBudgetCell(b, section: "Ingresos", line: i.line, name: i.name, column: "Real", value: $0) }
                    }
                }
            }
            HStack {
                TextField("Nuevo ingreso (p. ej. Paga extra)", text: $newIncome).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                    .onSubmit { store.addBudgetIncome(b, name: newIncome); newIncome = "" }
                Button("Añadir") { store.addBudgetIncome(b, name: newIncome); newIncome = "" }
                    .disabled(newIncome.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func linesCard(_ b: Budget, previous: [Budget]) -> some View {
        Card(title: "Partidas", icon: "list.bullet.rectangle",
             info: "«Real» es la suma de los movimientos de cada partida; si no tiene y está marcada como pagada, cuenta lo previsto. «Vs media» compara con los meses anteriores. Lo previsto se guarda al pulsar intro o al dejar de escribir.") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                GridRow {
                    Text(""); Text("Partida"); Text(""); Text("Previsto"); Text("Real"); Text("Tipo"); Text("Frecuencia"); Text("Vs media")
                }.font(.caption).foregroundStyle(.secondary)
                ForEach(b.lines) { l in
                    let r = b.real(l)
                    let past = previous.compactMap { p in p.line(named: l.name).map { p.real($0) } }.filter { $0 > 0 }
                    let avg = past.isEmpty ? nil : past.reduce(0, +) / Double(past.count)
                    GridRow {
                        // Sin nada previsto no hay pago que marcar (salvo que ya esté marcado, para poder quitarlo).
                        if l.isDiscretionary || !l.isDue(b.month) || (l.planned == 0 && !l.paid) { Color.clear.frame(width: 18, height: 18) } else {
                            Button {
                                store.setBudgetCell(b, section: "Partidas", line: l.line, name: l.name, column: "Pagado", value: l.paid ? "" : "✅")
                            } label: { Image(systemName: l.paid ? "checkmark.circle.fill" : "circle").foregroundStyle(l.paid ? Brand.good : .secondary) }
                                .buttonStyle(.plain).accessibilityLabel(l.paid ? "Marcar sin pagar" : "Marcar pagado")
                        }
                        HStack(spacing: 6) {
                            Button(l.name) { filter = l.name }.buttonStyle(.plain).lineLimit(1).foregroundStyle(l.isDue(b.month) ? .primary : .secondary)
                                .contextMenu {
                                    Button("Renombrar…") { renameText = l.name; renaming = l }
                                    Button("Quitar partida", role: .destructive) { store.removeBudgetLine(b, l) }
                                }
                            if !l.isDue(b.month) {
                                Text("toca en \(DayKey.esLong(Budget.firstDay(l.nextDue(from: b.month)) ?? Date(), .dateTime.month(.wide)))").font(.caption).foregroundStyle(Brand.info)
                            } else if let d = l.day { Text("día \(d)").font(.caption).foregroundStyle(.secondary) }
                        }
                        MiniBar(value: l.planned > 0 ? r / l.planned : 0, color: r > l.planned ? Brand.bad : l.kind == .ahorro ? Brand.sky : Brand.accent).frame(width: 110)
                        AmountCell(value: l.amount) { store.setBudgetCell(b, section: "Partidas", line: l.line, name: l.name, column: "Previsto", value: $0) }
                        Text(r == 0 ? "–" : Money.format(r)).monospacedDigit().fontWeight(.medium).foregroundStyle(r > l.planned ? Brand.bad : r == 0 ? .secondary : .primary)
                        ChoiceMenu(options: BudgetLine.Kind.allCases.map(\.rawValue), current: l.kind.rawValue, width: 96) {
                            store.setBudgetCell(b, section: "Partidas", line: l.line, name: l.name, column: "Tipo", value: $0)
                        }
                        frequencyMenu(b, l)
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
            // Movimientos con una partida que no está en la tabla (escrita a mano, o de una partida quitada): cuentan
            // como gasto pero no se ven en ninguna fila. Se dice cuál falta y se puede crear con un clic.
            ForEach(b.unassignedByCategory, id: \.name) { u in
                HStack(spacing: 8) {
                    Label("\(Money.exact(u.total)) en «\(u.name.isEmpty ? "sin partida" : u.name)», que no está en la tabla", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Brand.warn)
                    Button("Ver") { filter = u.name }.buttonStyle(.accentLink).font(.caption)
                    if !u.name.isEmpty {
                        Button("Crear partida") { store.addBudgetLine(b, name: u.name, amount: 0, kind: .variable, every: 1, start: nil) }.buttonStyle(.accentLink).font(.caption)
                    }
                }
            }
            Divider()
            HStack {
                TextField("Nueva partida (p. ej. Seguro vivienda)", text: $newLine).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                    .onSubmit { addLine(b) }
                ChoiceMenu(options: BudgetLine.Kind.allCases.map(\.rawValue), current: newKind.rawValue, width: 96) { newKind = BudgetLine.Kind(rawValue: $0) ?? .fijo }
                ChoiceMenu(options: BudgetLine.frequencies.map(\.label), current: BudgetLine.frequencyLabel(newEvery), width: 130) { label in
                    newEvery = BudgetLine.frequencies.first { $0.label == label }?.months ?? 1
                }
                Button("Añadir partida") { addLine(b) }.disabled(newLine.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Clic derecho en una partida para renombrarla o quitarla. Las no mensuales tocan este mes; cambia el mes en su menú de frecuencia.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .alert("Renombrar partida", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nombre", text: $renameText)
            Button("Renombrar") { if let l = renaming { store.renameBudgetLine(b, l, to: renameText) }; renaming = nil }
            Button("Cancelar", role: .cancel) { renaming = nil }
        } message: { Text("Sus movimientos de este mes pasan al nombre nuevo.") }
    }

    /// Frecuencia y, si no es mensual, el mes en que toca. Elegir «Cada 3 meses» la hace tocar este mes; el mes se cambia en el mismo menú.
    private func frequencyMenu(_ b: Budget, _ l: BudgetLine) -> some View {
        Menu {
            ForEach(BudgetLine.frequencies, id: \.months) { f in
                Button { store.setBudgetFrequency(b, l, every: f.months, start: l.every == f.months ? l.start : b.month) } label: {
                    if f.months == l.every { Label(f.label, systemImage: "checkmark") } else { Text(f.label) }
                }
            }
            if l.every > 1, let m = BudgetLine.monthIndex(b.month) {
                Divider()
                Section("Próximo cargo") {
                    ForEach(0..<l.every, id: \.self) { k in
                        let month = BudgetLine.month(m + k)
                        Button { store.setBudgetFrequency(b, l, every: l.every, start: month) } label: {
                            let name = Budget.title(month)
                            if l.nextDue(from: b.month) == month { Label(name, systemImage: "checkmark") } else { Text(name) }
                        }
                    }
                }
            }
        } label: {
            Text(l.every == 1 ? "Mensual" : BudgetLine.frequencyLabel(l.every)).font(.caption).foregroundStyle(l.every == 1 ? .secondary : Brand.info)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    private func reserveCard(_ b: Budget) -> some View {
        let lines = b.lines.filter { $0.every > 1 }.sorted { $0.nextDue(from: b.month) < $1.nextDue(from: b.month) }
        let total = lines.reduce(0) { $0 + $1.monthlyReserve }
        return Card(title: "Cargos que no son de cada mes", icon: "calendar.badge.clock",
                    info: "Lo que pagas cada 2, 3, 6 o 12 meses solo cuenta el mes en que toca. Apartar cada mes la parte que le corresponde evita que ese mes te pille. La frecuencia se cambia en la tabla de partidas.") {
            Text("Aparta \(Money.format(total)) al mes y tendrás cubiertos estos cargos cuando lleguen.").font(.callout)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow { Text("Partida"); Text("Importe"); Text("Frecuencia"); Text("Próximo"); Text("Al mes") }.font(.caption).foregroundStyle(.secondary)
                ForEach(lines) { l in
                    let next = l.nextDue(from: b.month)
                    GridRow {
                        Text(l.name).lineLimit(1)
                        Text(Money.format(l.amount)).monospacedDigit()
                        Text(BudgetLine.frequencyLabel(l.every)).foregroundStyle(.secondary)
                        Text(next == b.month ? "este mes" : DayKey.esLong(Budget.firstDay(next) ?? Date(), .dateTime.month(.wide).year())).foregroundStyle(next == b.month ? Brand.warn : .secondary)
                        Text(Money.format(l.monthlyReserve)).monospacedDigit().fontWeight(.medium)
                    }
                }
            }
        }
    }

    private func addLine(_ b: Budget) {
        store.addBudgetLine(b, name: newLine, amount: 0, kind: newKind, every: newEvery, start: b.month)
        newLine = ""; newEvery = 1; newKind = .fijo
    }

    private func trend(_ r: Double, _ avg: Double?) -> String {
        guard let avg, avg > 0, r > 0 else { return "" }
        let d = Int(((r - avg) / avg * 100).rounded())
        return abs(d) < 3 ? "=" : (d > 0 ? "+\(d) %" : "−\(-d) %")
    }

    private func movesCard(_ b: Budget) -> some View {
        let all = b.moves.sorted { ($0.date, $0.line) > ($1.date, $1.line) }
        let byCategory = filter.map { f in all.filter { $0.key == MD.fold(f) } } ?? all
        let q = MD.fold(search)
        let shown = q.isEmpty ? byCategory : byCategory.filter { MD.fold($0.note + " " + $0.category).contains(q) || Edit.budgetNumber($0.amount).contains(q) }
        let filtered = filter != nil || !q.isEmpty
        return Card(title: filter.map { "Movimientos · \($0)" } ?? "Movimientos", icon: "list.dash", actionTitle: filtered ? "Ver todos" : nil, action: { filter = nil; search = "" }) {
            if all.count > 8 || !q.isEmpty {
                TextField("Buscar en la nota o el importe", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
            }
            if shown.isEmpty { EmptyNote(!filtered ? "Aún no hay gastos apuntados este mes." : "Ningún gasto con ese filtro.", icon: "tray") }
            ForEach(shown.prefix(40)) { m in MoveRow(budget: b, move: m, categories: b.lines.map(\.name)) }
            if shown.count > 40 { Text("y \(shown.count - 40) más en la nota del mes").font(.caption).foregroundStyle(.secondary) }
            if filtered, !shown.isEmpty {
                Text("\(shown.count) \(shown.count == 1 ? "movimiento" : "movimientos") · \(Money.exact(shown.reduce(0) { $0 + $1.amount }))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
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
struct MiniBar: View {
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

    private func commit() {
        let new = text.trimmingCharacters(in: .whitespaces).isEmpty ? "" : Edit.budgetNumber(Money.parse(text))
        if new != current { save(new) }
    }

    var body: some View {
        TextField("–", text: $text).multilineTextAlignment(.trailing).monospacedDigit().frame(width: 80)
            .onSubmit(commit)
            .autosave(on: text, delay: 2, commit)
            .onAppear { text = current }
            .onChange(of: value) { text = current }
    }
}

private struct MoveRow: View {
    @Environment(Store.self) private var store
    let budget: Budget
    let move: BudgetMove
    let categories: [String]
    @State private var hover = false
    @State private var editing = false

    var body: some View {
        HStack(spacing: 10) {
            Text(DayKey.esLong(move.date, .dateTime.day().month(.abbreviated))).font(.callout).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
            Text(move.category).font(.callout).lineLimit(1).frame(width: 190, alignment: .leading)
            Text(MDParser.inline(move.note)).font(.callout).lineLimit(1)
            Spacer()
            // Una devolución (importe negativo) se ve como dinero que vuelve.
            Text(move.amount < 0 ? "+" + Money.exact(-move.amount) : Money.exact(move.amount)).monospacedDigit().fontWeight(.medium)
                .foregroundStyle(move.amount < 0 ? Brand.good : .primary)
            Button { editing = true } label: { Image(systemName: "pencil").accessibilityLabel("Corregir gasto") }
                .buttonStyle(.borderless).opacity(hover || editing ? 1 : 0)
                .popover(isPresented: $editing, arrowEdge: .trailing) { MoveEditor(budget: budget, move: move) }
            Button { store.deleteExpense(budget, move) } label: { Image(systemName: "trash").accessibilityLabel("Borrar gasto") }
                .buttonStyle(.borderless).opacity(hover ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { editing = true }
        .contextMenu {
            Button("Corregir…") { editing = true }
            // Corregir la partida también enseña al adivinador: la próxima vez que escribas lo mismo irá aquí.
            Menu("Cambiar partida") {
                ForEach(categories, id: \.self) { c in
                    Button(c) { store.setExpenseCategory(budget, move, to: c) }.disabled(MD.fold(c) == move.key)
                }
            }
            Button("Borrar gasto", role: .destructive) { store.deleteExpense(budget, move) }
        }
    }
}

/// Corregir un gasto ya apuntado: importe, fecha y nota. Una fecha de otro mes lo pasa a la nota de ese mes.
private struct MoveEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let budget: Budget
    let move: BudgetMove
    @State private var amount = ""
    @State private var date = Date()
    @State private var note = ""

    private var value: Double? {
        let t = amount.trimmingCharacters(in: .whitespaces)
        let v = Money.parse(t)
        return t.isEmpty || v == 0 ? nil : v
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Corregir gasto · \(move.category)").font(.headline)
            HStack {
                TextField("Importe", text: $amount).textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 100).onSubmit(save)
                Text("€").foregroundStyle(.secondary)
                DatePicker("", selection: $date, displayedComponents: .date).labelsHidden()
            }
            TextField("Nota", text: $note).textFieldStyle(.roundedBorder).frame(width: 280).onSubmit(save)
            if Budget.monthKey(date) != budget.month {
                Text("Pasará a la nota de \(Budget.title(Budget.monthKey(date)).lowercased()).").font(.caption).foregroundStyle(Brand.info)
            }
            Text("Un importe negativo es una devolución.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Guardar", action: save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(value == nil)
            }
        }
        .padding(16)
        .onAppear { amount = Edit.budgetNumber(move.amount); date = move.date; note = move.note }
    }

    private func save() {
        guard let v = value else { return }
        store.updateExpense(budget, move, date: DayKey.calendar().startOfDay(for: date), amount: v, note: note)
        dismiss()
    }
}
