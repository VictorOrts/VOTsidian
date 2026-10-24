import Charts
import SwiftUI

/// Orden y visibilidad de las tarjetas de Inicio. Se guarda como «id:1,id:0,…» (1 visible, 0 oculta).
enum HomeCard: String, CaseIterable, Identifiable {
    case atencion, hoy, peso, medicacion, tareas, habitos, mascota, nutricion, gastos, vehiculo, suscripciones, prestamos, viajes, lecturas, tramites
    var id: String { rawValue }
    var title: String {
        switch self {
        case .atencion: "Atención"
        case .hoy: "Hoy"
        case .peso: "Peso"
        case .medicacion: "Medicación"
        case .tareas: "Tareas de la semana"
        case .habitos: "Hábitos"
        case .mascota: "Mascota"
        case .nutricion: "Plan nutricional"
        case .gastos: "Gastos"
        case .vehiculo: "Vehículo"
        case .suscripciones: "Suscripciones"
        case .prestamos: "Préstamos y deudas"
        case .viajes: "Viajes"
        case .lecturas: "Lecturas"
        case .tramites: "Trámites y seguros"
        }
    }
    var full: Bool { self == .atencion || self == .hoy }
    /// Módulo del que es la tarjeta: si está oculto, la tarjeta tampoco sale.
    var module: Module? {
        switch self {
        case .peso: .peso
        case .medicacion: .medicacion
        case .mascota: .mascota
        case .nutricion: .nutricion
        case .gastos: .finanzas
        case .vehiculo: .vehiculo
        case .suscripciones: .suscripciones
        case .prestamos: .prestamos
        case .viajes: .viajes
        case .lecturas: .lecturas
        case .tramites: .tramites
        default: nil
        }
    }
}

struct HomeLayout: Equatable {
    var items: [(card: HomeCard, visible: Bool)]

    static let standard = HomeLayout(items: HomeCard.allCases.map { ($0, true) })

    static func == (a: HomeLayout, b: HomeLayout) -> Bool { a.items.map(\.card) == b.items.map(\.card) && a.items.map(\.visible) == b.items.map(\.visible) }

    init(items: [(card: HomeCard, visible: Bool)]) { self.items = items }

    /// Lee lo guardado; ignora ids desconocidos y añade al final las tarjetas nuevas.
    init(raw: String) {
        var out: [(HomeCard, Bool)] = []
        for part in raw.split(separator: ",") {
            let kv = part.split(separator: ":")
            guard kv.count == 2, let c = HomeCard(rawValue: String(kv[0])), !out.contains(where: { $0.0 == c }) else { continue }
            out.append((c, kv[1] != "0"))
        }
        for c in HomeCard.allCases where !out.contains(where: { $0.0 == c }) { out.append((c, true)) }
        self.items = out
    }

    var raw: String { items.map { "\($0.card.rawValue):\($0.visible ? 1 : 0)" }.joined(separator: ",") }

    mutating func move(_ card: HomeCard, by delta: Int) {
        guard let i = items.firstIndex(where: { $0.card == card }) else { return }
        let j = min(max(i + delta, 0), items.count - 1)
        guard i != j else { return }
        items.swapAt(i, j)
    }

    mutating func setVisible(_ card: HomeCard, _ v: Bool) {
        if let i = items.firstIndex(where: { $0.card == card }) { items[i].visible = v }
    }

    /// Filas para pintar: las tarjetas anchas van solas y las medianas de dos en dos.
    var rows: [[HomeCard]] {
        var rows: [[HomeCard]] = []
        var pending: HomeCard?
        for (c, v) in items where v {
            if c.full {
                if let p = pending { rows.append([p]); pending = nil }
                rows.append([c])
            } else if let p = pending { rows.append([p, c]); pending = nil }
            else { pending = c }
        }
        if let p = pending { rows.append([p]) }
        return rows
    }
}

struct InicioView: View {
    @Environment(Store.self) private var store
    let go: (Screen) -> Void
    @State private var quick = ""
    @State private var quickMsg = ""
    @AppStorage("inicioLayout") private var layoutRaw = ""
    @State private var customizing = ProcessInfo.processInfo.environment["VOT_CUSTOMIZE"] != nil

    private var upcomingTasks: [TaskItem] {
        let limit = DayKey.adding(days: 7, to: DayKey.today())
        return store.tasks.filter { t in
            !t.done && ((t.due.map { $0 <= limit } ?? false) || (t.scheduled.map { $0 <= limit } ?? false))
        }.sorted { ($0.due ?? $0.scheduled ?? .distantFuture) < ($1.due ?? $1.scheduled ?? .distantFuture) }
    }

    /// Cuenta sin ordenar: el resumen solo necesita el número.
    private var upcomingCount: Int {
        let limit = DayKey.adding(days: 7, to: DayKey.today())
        return store.tasks.reduce(0) { n, t in
            n + (!t.done && ((t.due.map { $0 <= limit } ?? false) || (t.scheduled.map { $0 <= limit } ?? false)) ? 1 : 0)
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 6 ? "Buenas noches" : h < 14 ? "Buenos días" : h < 21 ? "Buenas tardes" : "Buenas noches"
    }

    private var summary: String {
        var parts: [String] = []
        if store.isVisible(.peso), let r = store.weight.remainingKg { parts.append("Faltan \(fmt(r)) kg para tu objetivo") }
        if store.isVisible(.medicacion), let d = store.medicacion.daysUntilNext, let main = store.medicacion.main { parts.append("\(main.act) de \(main.name) \(relativeDays(d))") }
        let pills = store.medicacion.pending().filter { $0.med.every == 1 }.count
        if store.isVisible(.medicacion), pills > 0 { parts.append(pills == 1 ? "1 toma pendiente hoy" : "\(pills) medicamentos por tomar hoy") }
        let n = upcomingCount
        if n > 0 { parts.append("\(n) \(n == 1 ? "tarea" : "tareas") esta semana") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let _ = BodyCounter.hit("InicioView")
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting).font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(capitalizedFirst(longDate(Date()))).font(.title3).foregroundStyle(.secondary)
                        if !summary.isEmpty { Text(summary).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button { customizing.toggle() } label: { Label(customizing ? "Listo" : "Personalizar", systemImage: customizing ? "checkmark" : "slider.horizontal.3") }
                        .controlSize(.small)
                }
                let layout = HomeLayout(raw: layoutRaw)
                // Se pinta sin las tarjetas de módulos ocultos, pero los cambios se guardan sobre el orden completo.
                let shown = HomeLayout(items: layout.items.filter { $0.card.module.map { !store.hiddenModules.contains($0) } ?? true })
                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    ForEach(Array(shown.rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            if row.count == 2 {
                                homeCard(row[0], layout); homeCard(row[1], layout)
                            } else if row[0].full {
                                homeCard(row[0], layout).gridCellColumns(2)
                            } else {
                                homeCard(row[0], layout); Color.clear
                            }
                        }
                    }
                }
                if customizing { hiddenCards(layout) }
            }
            .padding(28)
            .readableWidth()
        }
        .navigationTitle("Inicio")
        .onAppear {
            let key = DayKey.weekKey(Date())
            if store.reviews[key] == nil { store.createReview(key: key, monday: DayKey.weekStart(Date())) }
        }
    }

    // MARK: Hoy

    private var todayCard: some View {
        let today = DayKey.today()
        let items = (store.agenda(from: today, to: today)[DayKey.string(today)] ?? []).filter { $0.kind != .done && $0.kind != .diary }
        let overdue = store.tasks.filter { !$0.done && ($0.due.map { $0 < today } ?? false) }
        return Card(title: "Hoy", icon: "sun.max", actionTitle: "Calendario", action: { go(.calendario) }) {
            HStack {
                TextField("Añadir tarea… (ej: llamar al dentista el viernes)", text: $quick).onSubmit(addQuick)
                Button("Añadir", action: addQuick).buttonStyle(.borderedProminent).disabled(quick.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !quickMsg.isEmpty { Label(quickMsg, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(Brand.accent) }
            HStack(spacing: 12) {
                Text("¿Cómo vas hoy?").foregroundStyle(.secondary)
                MoodPicker(value: store.diaryValue(today, "animo")) { store.setDiaryValue(today, "animo", $0) }
                Spacer()
                Button { store.openToday() } label: { Label("Nota de hoy", systemImage: "note.text") }.controlSize(.small)
                Button { store.showCierre = true } label: { Label("Cerrar el día", systemImage: "moon.stars") }.controlSize(.small)
            }
            ForEach(overdue.prefix(4)) { TaskRow(task: $0) }
            ForEach(items.prefix(8)) { it in
                if let t = it.task { TaskRow(task: t) }
                else {
                    HStack(spacing: 9) {
                        Image(systemName: it.kind.icon).foregroundStyle(it.kind.color).frame(width: 18)
                        if let h = it.timeText { Text(h).monospacedDigit().foregroundStyle(.secondary) }
                        Text(MDParser.inline(it.title))
                        if !it.detail.isEmpty { Text(it.detail).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if let s = it.screen { Button { go(s) } label: { Image(systemName: "chevron.right").accessibilityLabel("Siguiente / abrir") }.buttonStyle(.borderless).foregroundStyle(.tertiary) }
                    }
                }
            }
            if items.isEmpty && overdue.isEmpty { EmptyNote("Nada programado para hoy.", icon: "checkmark.circle") }
        }
    }

    private func addQuick() {
        let raw = quick.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        let p = NaturalDate.extractTask(raw)
        store.addTask(p.text, due: p.date, recurrence: p.recurrence, priority: p.priority)
        quickMsg = (p.date.map { "Añadida para \(longDate($0))" } ?? "Añadida al Inbox") + (p.recurrence.map { " · \(Recurrence.describe($0))" } ?? "")
        quick = ""
    }

    @ViewBuilder private func homeCard(_ c: HomeCard, _ layout: HomeLayout) -> some View {
        Group {
            switch c {
            case .atencion: attention
            case .hoy: todayCard
            case .peso: pesoCard
            case .medicacion: medicacionCard
            case .tareas: tasksCard
            case .habitos: weekCard
            case .mascota: mascotaCard
            case .nutricion: nutritionCard
            case .gastos: gastosCard
            case .vehiculo: vehiculoCard
            case .suscripciones: suscripcionesCard
            case .prestamos: prestamosCard
            case .viajes: viajesCard
            case .lecturas: lecturasCard
            case .tramites: tramitesCard
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if customizing {
                HStack(spacing: 2) {
                    Button { var l = layout; l.move(c, by: -1); layoutRaw = l.raw } label: { Image(systemName: "arrow.up").accessibilityLabel("Subir") }.help("Subir")
                    Button { var l = layout; l.move(c, by: 1); layoutRaw = l.raw } label: { Image(systemName: "arrow.down").accessibilityLabel("Bajar") }.help("Bajar")
                    Button { var l = layout; l.setVisible(c, false); layoutRaw = l.raw } label: { Image(systemName: "eye.slash").accessibilityLabel("Ocultar") }.help("Ocultar")
                }
                .buttonStyle(.bordered).controlSize(.small).padding(10)
            }
        }
        .overlay { if customizing { RoundedRectangle(cornerRadius: Brand.radiusLarge).stroke(Brand.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])) } }
    }

    @ViewBuilder private func hiddenCards(_ layout: HomeLayout) -> some View {
        let hidden = layout.items.filter { !$0.visible && ($0.card.module.map { !store.hiddenModules.contains($0) } ?? true) }.map(\.card)
        HStack(spacing: 10) {
            Text("Ocultas:").foregroundStyle(.secondary)
            if hidden.isEmpty { Text("ninguna").foregroundStyle(.secondary) }
            ForEach(hidden) { c in
                Button { var l = layout; l.setVisible(c, true); layoutRaw = l.raw } label: { Label(c == .medicacion ? store.medicacion.name : c == .mascota ? store.mascota.name : c == .vehiculo ? store.vehiculo.name : c.title, systemImage: "eye") }.controlSize(.small)
            }
            Spacer()
            Button("Restablecer orden") { layoutRaw = "" }.controlSize(.small)
        }
    }

    @ViewBuilder private var attention: some View {
        let list = store.currentAlerts
        Card(title: list.isEmpty ? "Todo al día" : "Atención", icon: list.isEmpty ? "checkmark.seal" : "bell.badge") {
            AlertList(alerts: list, limit: 6, go: go)
        }
    }

    // MARK: Peso

    private var pesoCard: some View {
        let w = store.weight
        return Card(title: "Peso", icon: "scalemass", actionTitle: "Abrir", action: { go(.peso) }) {
            if let l = w.last {
                HStack(spacing: 20) {
                    Ring(progress: w.progress, color: Brand.accent) {
                        VStack(spacing: 0) {
                            Text("\(Int(w.progress * 100))%").font(.system(size: 26, weight: .bold, design: .rounded))
                            Text("del camino").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fmt(l.kg, unit: " kg")).font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(DayKey.dmy(l.date) + (w.previous.map { " · \(fmtDelta(l.kg - $0.kg)) vs el anterior" } ?? ""))
                            .font(.callout).foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            Label("\(fmt(w.achievedKg)) kg \(w.achievedWord)", systemImage: w.gaining ? "arrow.up.right" : "arrow.down.right").foregroundStyle(Brand.accent)
                            Text("faltan \(fmt(w.remainingKg)) kg")
                        }.font(.callout)
                    }
                }
                Sparkline(records: thinnedKeepingExtremes(w.records, to: 120), goal: w.hasGoal ? w.goalKg : nil).frame(height: 70)
                let days = DayKey.days(from: l.date, to: DayKey.today())
                if days > 31 {
                    Label("Hace \(days) días que no registras el peso.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Brand.warn).font(.callout)
                }
            } else {
                EmptyNote("Sin registros de peso.")
            }
        }
    }

    // MARK: Medicación

    private var medicacionCard: some View {
        let m = store.medicacion
        let daily = m.active().filter { $0.every == 1 }
        return Card(title: m.name, icon: m.main?.icon ?? "pills", actionTitle: "Abrir", action: { go(.medicacion) }) {
            if let main = m.main, let last = m.last, let next = m.next, let d = m.daysUntilNext {
                let color: Color = d < 0 ? Brand.bad : d == 0 ? Brand.warn : Brand.accent
                HStack(spacing: 20) {
                    Ring(progress: d <= 0 ? 1 : 1 - Double(d) / Double(m.everyDays), color: color) {
                        VStack(spacing: 0) {
                            Text(d == 0 ? "hoy" : "\(abs(d))").font(.system(size: 30, weight: .bold, design: .rounded))
                            if d != 0 { Text(d < 0 ? "de retraso" : d == 1 ? "día" : "días").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Próximo").font(.caption).foregroundStyle(.secondary)
                        Text(capitalizedFirst(longDate(next))).font(.title3.weight(.semibold))
                        Text("Último: \(DayKey.dmy(last.date)) · \(last.dose) · \(last.site)").font(.callout).foregroundStyle(.secondary)
                        Text("\(main.name) · " + plural(m.doses.count, main.act, main.act + "s") + " · cada \(m.everyDays) días").font(.callout).foregroundStyle(.secondary)
                    }
                }
                if d <= 1, m.last?.date != DayKey.today() {
                    Button { store.injectToday() } label: { Label(main.isInjection ? "Me pinché hoy" : "Tomada hoy", systemImage: "checkmark.circle") }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .help("Registra \(last.dose)" + (main.isInjection ? ", \(m.suggestedSite)" : "") + ". Se puede deshacer.")
                }
                if d < 0 {
                    Label("Atrasado \(-d) \(-d == 1 ? "día" : "días"). Regístralo cuando te lo pongas.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Brand.warn).font(.callout)
                }
            } else if daily.isEmpty {
                EmptyNote(m.meds.isEmpty ? "Sin medicamentos. Añádelos en \(m.name)." : "Nada que tomar hoy.")
            }
            // Las tomas diarias, con una casilla por toma.
            ForEach(daily) { med in
                HStack(spacing: 10) {
                    Image(systemName: med.icon).foregroundStyle(Brand.accent).frame(width: 18)
                    Text(med.name + (med.dose.isEmpty ? "" : " · \(med.dose)")).lineLimit(1)
                    Spacer()
                    IntakeChecks(med: med)
                }.font(.callout)
            }
        }
    }

    // MARK: Tareas, hábitos

    private var tasksCard: some View {
        Card(title: "Tareas de hoy y próximos 7 días", icon: "checklist", actionTitle: "Todas", action: { go(.tareas) }) {
            let upcoming = upcomingTasks
            if upcoming.isEmpty {
                EmptyNote("Nada pendiente en los próximos 7 días.", icon: "checkmark.circle")
            } else {
                ForEach(upcoming.prefix(7)) { TaskRow(task: $0) }
            }
        }
    }

    private var weekCard: some View {
        let key = DayKey.weekKey(Date())
        let r = store.reviews[key]
        let todayIdx = (Calendar(identifier: .iso8601).component(.weekday, from: Date()) + 5) % 7
        return Card(title: "Hábitos · semana \(key.suffix(3))", icon: "checkmark.circle", actionTitle: r == nil ? "Crear revisión" : "Abrir", action: { go(.semana) }) {
            if let r {
                ForEach(r.habits, id: \.name) { h in
                    HStack(spacing: 10) {
                        Text(h.name).frame(width: 90, alignment: .leading)
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { d in
                                Button { store.toggleHabit(key: key, habit: h.name, day: d) } label: {
                                    Circle().fill(h.days[d] ? Brand.accent : Color.secondary.opacity(0.2))
                                        .frame(width: 16, height: 16)
                                        .overlay(Circle().stroke(d == todayIdx ? Color.primary.opacity(0.6) : .clear, lineWidth: 1.5))
                                }.buttonStyle(.plain).help("Marcar o desmarcar")
                            }
                        }
                        Spacer()
                        Text("\(h.count)/7").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Spacer().frame(width: 100)
                    ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).frame(width: 16) }
                }
            } else {
                EmptyNote("Todavía no hay revisión para esta semana.")
            }
        }
    }

    // MARK: Mascota, nutrición

    private var mascotaCard: some View {
        let n = store.mascota
        return Card(title: n.name, icon: "pawprint", actionTitle: "Abrir", action: { go(.mascota) }) {
            ForEach(Array(n.overdue.enumerated()), id: \.offset) { _, o in
                Label("\(o.title) vencida el \(DayKey.dmy(o.date))", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Brand.warn)
            }
            ForEach(Array(n.upcoming.prefix(3).enumerated()), id: \.offset) { _, u in
                Label("\(u.title): \(DayKey.dmy(u.date)) (\(relativeDays(DayKey.days(from: DayKey.today(), to: u.date))))", systemImage: "calendar")
            }
            if n.overdue.isEmpty && n.upcoming.isEmpty { Label("Sin citas ni vacunas programadas", systemImage: "checkmark.seal").foregroundStyle(.secondary) }
            if let last = n.visits.last { Text("Último registro: \(DayKey.dmy(last.date)) · \(last.tipo)").font(.callout).foregroundStyle(.secondary) }
        }
    }

    // MARK: Vehículo, dinero, viajes y lecturas

    private var vehiculoCard: some View {
        let v = store.vehiculo
        let today = DayKey.today()
        let alerts = store.vehiculoAlerts(today: today)
        return Card(title: v.name, icon: "car", actionTitle: "Abrir", action: { go(.vehiculo) }) {
            if let km = v.currentKm { Label(Vehiculo.kmText(km), systemImage: "gauge.with.dots.needle.50percent") }
            ForEach(alerts.prefix(3)) { a in
                Label(a.text.replacingOccurrences(of: "\(v.name): ", with: ""), systemImage: a.level == .urgent ? "exclamationmark.triangle.fill" : "calendar")
                    .foregroundStyle(a.level == .urgent ? Brand.warn : .primary)
            }
            if alerts.isEmpty {
                if let d = v.dues.first(where: { $0.date >= today }) {
                    Label("\(d.name): \(DayKey.dmy(d.date)) (\(relativeDays(DayKey.days(from: today, to: d.date))))", systemImage: "calendar").foregroundStyle(.secondary)
                } else { Label("Sin fechas ni mantenimiento pendientes", systemImage: "checkmark.seal").foregroundStyle(.secondary) }
            }
        }
    }

    private var suscripcionesCard: some View {
        let s = store.suscripciones
        let today = DayKey.today()
        return Card(title: "Suscripciones", icon: "repeat", actionTitle: "Abrir", action: { go(.suscripciones) }) {
            if s.items.isEmpty { Label("Aún no hay ninguna", systemImage: "tray").foregroundStyle(.secondary) } else {
                HStack(spacing: 22) {
                    macro("al mes", Money.format(s.monthlyTotal), Brand.violet)
                    macro("al año", Money.format(s.yearlyTotal), Brand.info)
                }
                ForEach(s.upcoming(today: today).prefix(3), id: \.item.id) { entry in
                    Label("\(entry.item.name): \(Money.exact(entry.item.amount)) \(relativeDays(DayKey.days(from: today, to: entry.date)))", systemImage: entry.item.status == .trial ? "hourglass" : "calendar")
                        .foregroundStyle(entry.item.status == .trial ? Brand.warn : .primary)
                }
            }
        }
    }

    private var prestamosCard: some View {
        let p = store.prestamos
        let today = DayKey.today()
        let open = p.statuses(today: today).filter { !$0.isPaidOff }
        return Card(title: "Préstamos y deudas", icon: "creditcard.and.123", actionTitle: "Abrir", action: { go(.prestamos) }) {
            if open.isEmpty { Label(p.loans.isEmpty ? "Aún no hay ninguno" : "Todo pagado", systemImage: p.loans.isEmpty ? "tray" : "checkmark.seal").foregroundStyle(.secondary) } else {
                HStack(spacing: 22) {
                    macro("debes", Money.format(p.totalRemaining(today: today)), Brand.bad)
                    macro("cuotas al mes", Money.format(p.monthlyInstallments(today: today)), Brand.amber)
                }
                ForEach(open.prefix(3)) { s in
                    Label(s.loan.name + (s.nextDue.map { ": cuota \(relativeDays(DayKey.days(from: today, to: $0)))" } ?? ": quedan \(Money.exact(s.remaining))"), systemImage: s.missed ? "exclamationmark.triangle.fill" : "calendar")
                        .foregroundStyle(s.missed ? Brand.warn : .primary)
                }
            }
        }
    }

    private var viajesCard: some View {
        let v = store.viajes
        let today = DayKey.today()
        let trips = v.upcoming(today: today)
        return Card(title: "Viajes", icon: "airplane", actionTitle: "Abrir", action: { go(.viajes) }) {
            if trips.isEmpty { Label("Ningún viaje por venir", systemImage: "tray").foregroundStyle(.secondary) }
            ForEach(trips.prefix(3)) { t in
                VStack(alignment: .leading, spacing: 2) {
                    Label(t.name + (t.start.map { v.isOngoing(t, today: today) ? " · en curso" : " · \(relativeDays(DayKey.days(from: today, to: $0)))" } ?? ""), systemImage: "airplane.departure")
                    if t.budget > 0 { Text("\(Money.exact(v.spent(t))) de \(Money.exact(t.budget))").font(.callout).foregroundStyle(v.spent(t) > t.budget ? Brand.bad : .secondary) }
                }
            }
        }
    }

    private var lecturasCard: some View {
        let l = store.lecturas
        let year = DayKey.calendar().component(.year, from: DayKey.today())
        let done = l.finished(in: year).count
        return Card(title: "Lecturas", icon: "book", actionTitle: "Abrir", action: { go(.lecturas) }) {
            if l.books.isEmpty { Label("Aún no hay libros", systemImage: "tray").foregroundStyle(.secondary) } else {
                Label(l.goal > 0 ? "\(done) de \(l.goal) este año" : "\(plural(done, "libro", "libros")) este año", systemImage: "checkmark.seal")
                if l.goal > 0 { ProgressView(value: Double(min(done, l.goal)), total: Double(l.goal)).tint(Brand.accent) }
                ForEach(l.reading.prefix(2)) { b in Label(b.title, systemImage: "book").foregroundStyle(.secondary) }
            }
        }
    }

    private var tramitesCard: some View {
        let d = store.tramites
        let today = DayKey.today()
        let soon = d.pendingProcedures.prefix(3)
        let renewals = d.insurances.compactMap { i in i.nextRenewal(from: today).map { (i.name, $0) } }.sorted { $0.1 < $1.1 }.prefix(2)
        return Card(title: "Trámites y seguros", icon: "building.columns", actionTitle: "Abrir", action: { go(.tramites) }) {
            if soon.isEmpty && renewals.isEmpty { Label("Sin plazos ni renovaciones", systemImage: "checkmark.seal").foregroundStyle(.secondary) }
            ForEach(Array(soon), id: \.procedure.id) { e in
                let n = DayKey.days(from: today, to: e.due)
                Label("\(e.procedure.name): \(n < 0 ? "venció " + relativeDays(n) : relativeDays(n))", systemImage: n < 0 ? "exclamationmark.triangle.fill" : "calendar")
                    .foregroundStyle(n < 0 ? Brand.bad : n <= 30 ? Brand.warn : .primary)
            }
            ForEach(Array(renewals), id: \.0) { name, date in
                Label("Seguro de \(name): renueva \(relativeDays(DayKey.days(from: today, to: date)))", systemImage: "shield.lefthalf.filled").foregroundStyle(.secondary)
            }
        }
    }

    /// Cómo va el mes en Gastos y el próximo pago fijo sin marcar.
    private var gastosCard: some View {
        let month = Budget.monthKey(DayKey.today())
        return Card(title: "Gastos", icon: "creditcard", actionTitle: "Abrir", action: { go(.gastos) }) {
            if let b = store.budget(month) {
                let s = BudgetStatus(b)
                HStack(spacing: 22) {
                    macro("hoy puedes", Money.format(s.leftToday), s.leftToday > 0 ? Brand.accent : Brand.bad)
                    macro("sobrará el \(s.days)", Money.format(s.endLeft), s.endLeft < 0 ? Brand.bad : Brand.info)
                    macro("gastado", Money.format(b.spent), Brand.amber)
                }
                let day = DayKey.calendar().component(.day, from: DayKey.today())
                if let next = b.lines.filter({ !$0.isDiscretionary && $0.isDue(month) && !$0.paid && b.real($0) == 0 && ($0.day ?? 0) >= day && $0.planned > 0 })
                    .min(by: { ($0.day ?? 99) < ($1.day ?? 99) }), let d = next.day {
                    Label("Próximo pago: \(next.name), \(Money.format(next.planned)) el día \(d)", systemImage: "calendar").font(.callout).foregroundStyle(.secondary)
                }
            } else if let near = store.nearestBudgetMonth(to: month) {
                EmptyNote("Sin presupuesto de \(Budget.title(month).lowercased()).", icon: "creditcard")
                Button("Ver \(Budget.title(near).lowercased())") { store.pendingGastosMonth = near; go(.gastos) }.buttonStyle(.accentLink)
            } else {
                EmptyNote("Sin presupuesto este mes.", icon: "creditcard")
            }
        }
    }

    private var nutritionCard: some View {
        let p = store.plan
        return Card(title: "Plan nutricional", icon: "fork.knife", actionTitle: "Abrir", action: { go(.nutricion) }) {
            if p.kcal > 0 {
                HStack(spacing: 22) {
                    macro("kcal", fmt(p.kcal, 0), Brand.accent)
                    macro("proteína", fmt(p.protein, 0, unit: " g"), Brand.info)
                    macro("hidratos", fmt(p.carbs, 0, unit: " g"), Brand.amber)
                    macro("grasas", fmt(p.fat, 0, unit: " g"), Brand.violet)
                }
                if let l = store.weight.last { Text("\(fmt(p.protein / l.kg)) g de proteína por kg con tu peso actual").font(.callout).foregroundStyle(.secondary) }
            } else {
                EmptyNote("Sin plan cargado.")
            }
        }
    }

    private func macro(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
            HStack(spacing: 5) { Circle().fill(color).frame(width: 8, height: 8); Text(label).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct Sparkline: View {
    let records: [WeightRecord]
    let goal: Double?

    var body: some View {
        let _ = BodyCounter.hit("Sparkline")
        let kgs = records.map(\.kg)
        let lo = (kgs + (goal.map { [$0] } ?? [])).min().map { $0 - 1 } ?? 0
        Chart {
            ForEach(records) { r in
                AreaMark(x: .value("Día", r.date), yStart: .value("Base", lo), yEnd: .value("kg", r.kg))
                    .foregroundStyle(LinearGradient(colors: [Brand.accent.opacity(0.35), Brand.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Día", r.date), y: .value("kg", r.kg)).foregroundStyle(Brand.accent).interpolationMethod(.monotone)
            }
            if let l = records.last { PointMark(x: .value("Día", l.date), y: .value("kg", l.kg)).foregroundStyle(Brand.accent).symbolSize(60) }
            if let goal { RuleMark(y: .value("Objetivo", goal)).foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])) }
        }
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .chartYScale(domain: lo...((kgs.max() ?? lo) + 1))
        .chartXScale(range: .plotDimension(padding: 6))
    }
}
