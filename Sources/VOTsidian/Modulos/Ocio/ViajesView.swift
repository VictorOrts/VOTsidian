import SwiftUI

struct ViajesView: View {
    @Environment(Store.self) private var store
    private let file = VaultPath.viajes
    @State private var name = ""
    @State private var hasDates = true
    @State private var start = Date()
    @State private var end = Date()
    @State private var budget = ""
    @State private var item = ""

    var body: some View {
        let _ = BodyCounter.hit("ViajesView")
        let v = store.viajes
        let today = DayKey.today()
        let upcoming = v.upcoming(today: today)
        let next = upcoming.first
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MissingNoteBanner(module: .viajes)
                HStack(spacing: 12) {
                    Tile(title: "Próximo viaje", value: next?.name ?? "–",
                         note: next.flatMap { t in t.start.map { s in v.isOngoing(t, today: today) ? "en curso" : relativeDays(DayKey.days(from: today, to: s)) + " · " + dayLabel(s) } })
                    Tile(title: "Presupuesto", value: Money.format(upcoming.reduce(0) { $0 + $1.budget }), note: "de los viajes por venir")
                    Tile(title: "Gastado", value: Money.format(upcoming.reduce(0) { $0 + v.spent($1) }), note: "en esos viajes")
                }
                Card(title: "Avisos", icon: "bell", info: "Avisa cuando un viaje está a menos de 30 días, si te pasas del presupuesto y si el pasaporte de Documentos caduca menos de 6 meses después de salir.") {
                    let alerts = store.viajeAlerts(today: today)
                    AlertList(alerts: alerts, emptyText: "Todo en orden.")
                }
                Card(title: "Viajes", icon: "airplane") {
                    if upcoming.isEmpty { EmptyNote("Añade tu próximo viaje abajo.", icon: "airplane") }
                    ForEach(upcoming) { t in
                        TripRow(trip: t, spent: v.spent(t), expenses: v.expenses.filter { MD.fold($0.trip) == MD.fold(t.name) }, ongoing: v.isOngoing(t, today: today))
                    }
                }
                let past = v.trips.filter { t in !upcoming.contains { $0.id == t.id } }.sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
                if !past.isEmpty {
                    Card(title: "Hechos y cancelados", icon: "checkmark.seal") {
                        ForEach(past.prefix(8)) { t in
                            HStack {
                                Text(t.name).foregroundStyle(.secondary)
                                if let s = t.start { Text(DayKey.esLong(s, .dateTime.month(.abbreviated).year())).font(.callout).foregroundStyle(.tertiary) }
                                Spacer()
                                if v.spent(t) > 0 || t.budget > 0 { Text(t.budget > 0 ? "\(Money.exact(v.spent(t))) de \(Money.exact(t.budget))" : Money.exact(v.spent(t))).monospacedDigit().foregroundStyle(.secondary) }
                                Text(t.status).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                Card(title: "Añadir viaje", icon: "plus.circle") {
                    HStack {
                        TextField("Destino", text: $name)
                        TextField("Presupuesto", text: $budget).frame(width: 110)
                    }
                    HStack {
                        Toggle("Con fechas", isOn: $hasDates).toggleStyle(.checkbox)
                        if hasDates {
                            DatePicker("Salida", selection: $start, displayedComponents: .date).fixedSize()
                            DatePicker("Vuelta", selection: $end, in: start..., displayedComponents: .date).fixedSize()
                        }
                        Spacer()
                        Button("Guardar") {
                            let cal = DayKey.calendar()
                            store.addViaje(name: name.trimmingCharacters(in: .whitespaces), start: hasDates ? cal.startOfDay(for: start) : nil,
                                           end: hasDates ? cal.startOfDay(for: max(start, end)) : nil, budget: Money.parse(budget) > 0 ? Money.parse(budget) : nil)
                            name = ""; budget = ""
                        }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Card(title: "Equipaje · \(v.packing.filter { !$0.done }.count) por meter", icon: "suitcase",
                     info: "Tu lista de siempre. Márcala al hacer la maleta y pulsa «Desmarcar todo» para dejarla lista para el próximo viaje. No cuenta como tareas.") {
                    if v.packing.isEmpty { EmptyNote("Añade lo que no puede faltar: cargador, DNI, botiquín…", icon: "suitcase") }
                    ForEach(v.packing) { p in
                        HStack(spacing: 10) {
                            Button { store.togglePacking(p) } label: { Image(systemName: p.done ? "checkmark.circle.fill" : "circle").foregroundStyle(p.done ? Brand.good : Brand.accent).accessibilityLabel(p.done ? "Sacar de la maleta" : "Meter en la maleta") }
                                .buttonStyle(.plain)
                            Text(p.text).strikethrough(p.done).foregroundStyle(p.done ? .secondary : .primary)
                            Spacer()
                            Button { store.deletePacking(p) } label: { Image(systemName: "minus.circle").accessibilityLabel("Quitar") }.buttonStyle(.borderless).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        TextField("Qué llevar", text: $item).onSubmit(addItem)
                        Button("Añadir", action: addItem).disabled(item.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Desmarcar todo") { store.uncheckPacking() }.disabled(v.packing.allSatisfy { !$0.done })
                    }.controlSize(.small)
                }
                NoteTables(file: file, icon: "tablecells", include: { MD.fold($0.title).contains("destino") || MD.fold($0.title).contains("gastos") })
                Button("Abrir la nota") { store.pendingNote = file }.buttonStyle(.accentLink)
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Viajes")
    }

    private func addItem() {
        let t = item.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.addPacking(t)
        item = ""
    }
}

/// Un viaje con su presupuesto y el formulario para apuntar un gasto.
private struct TripRow: View {
    @Environment(Store.self) private var store
    let trip: ViajesData.Trip
    let spent: Double
    let expenses: [ViajesData.Expense]
    let ongoing: Bool
    @State private var concept = ""
    @State private var amount = ""
    @State private var toGastos = true
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: ongoing ? "airplane.departure" : "airplane").foregroundStyle(Brand.rose).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(trip.name).fontWeight(.medium)
                    Text([trip.start.map { DayKey.dmy($0) + (trip.end.map { " – " + DayKey.dmy($0) } ?? "") }, trip.days.map { plural($0, "día", "días") }, trip.status.isEmpty ? nil : trip.status]
                        .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if trip.budget > 0 {
                    Text("\(Money.exact(spent)) de \(Money.exact(trip.budget))").monospacedDigit().foregroundStyle(spent > trip.budget ? Brand.bad : .secondary)
                } else if spent > 0 { Text(Money.exact(spent)).monospacedDigit().foregroundStyle(.secondary) }
                Button(open ? "Cerrar" : "Gastos") { open.toggle() }.controlSize(.small)
                Menu {
                    ForEach(["Idea", "Planeando", "Reservado", "Hecho", "Cancelado"], id: \.self) { st in Button(st) { store.setViajeStatus(trip, to: st) } }
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Cambiar estado") }.menuStyle(.borderlessButton).fixedSize()
            }
            if trip.budget > 0 { ProgressView(value: min(spent, trip.budget), total: trip.budget).tint(spent > trip.budget ? Brand.bad : Brand.accent) }
            if open {
                ForEach(expenses) { e in
                    HStack { Text(DayKey.dmy(e.date)).monospacedDigit().foregroundStyle(.secondary); Text(e.concept); Spacer(); Text(Money.exact(e.amount)).monospacedDigit() }.font(.callout)
                }
                HStack {
                    TextField("Concepto (vuelo, hotel, cena…)", text: $concept)
                    TextField("Importe", text: $amount).frame(width: 90)
                    if store.isVisible(.gastos) { Toggle("También en Gastos", isOn: $toGastos).toggleStyle(.checkbox) }
                    Button("Apuntar") {
                        store.addViajeGasto(trip, concept: concept.trimmingCharacters(in: .whitespaces), amount: Money.parse(amount), expense: toGastos && store.isVisible(.gastos))
                        concept = ""; amount = ""
                    }.disabled(concept.trimmingCharacters(in: .whitespaces).isEmpty || Money.parse(amount) <= 0)
                }.controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
