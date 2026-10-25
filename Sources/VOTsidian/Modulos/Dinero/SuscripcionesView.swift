import SwiftUI

struct SuscripcionesView: View {
    @Environment(Store.self) private var store
    private let file = VaultPath.suscripciones
    @State private var name = ""
    @State private var amount = ""
    @State private var every = "Mensual"
    @State private var date = Date()
    @State private var category = ""
    @State private var trial = false
    @State private var message = ""

    private static let periods = ["Semanal", "Mensual", "Trimestral", "Semestral", "Anual"]

    var body: some View {
        let _ = BodyCounter.hit("SuscripcionesView")
        let s = store.suscripciones
        let today = DayKey.today()
        let upcoming = s.upcoming(today: today)
        let cancelled = s.items.filter { $0.status == .cancelled }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MissingNoteBanner(module: .suscripciones)
                TileRow {
                    Tile(title: "Al mes", value: Money.format(s.monthlyTotal), note: "\(plural(s.active.count, "suscripción activa", "suscripciones activas"))")
                    Tile(title: "Al año", value: Money.format(s.yearlyTotal), note: s.active.isEmpty ? nil : "la más cara: \(s.active.max { $0.yearlyCost < $1.yearlyCost }!.name)")
                    Tile(title: "En prueba", value: "\(s.trials.count)", note: s.trials.isEmpty ? nil : "cancela antes de que acaben")
                }
                Card(title: "Avisos", icon: "bell",
                     info: "Avisa 7 días antes de cada renovación (14 si es anual) y cuando una prueba está a punto de acabar.") {
                    let alerts = store.suscripcionAlerts(today: today)
                    AlertList(alerts: alerts, emptyText: "Nada se renueva pronto.")
                }
                Card(title: "Próximos cobros", icon: "repeat",
                     info: "«Apuntar en Gastos» añade el cobro de hoy al mes, en la partida de la fila o en la que adivine Gastos.") {
                    if upcoming.isEmpty { EmptyNote("Añade tus suscripciones abajo.", icon: "repeat") }
                    ForEach(upcoming, id: \.item.id) { entry in
                        let i = entry.item, n = DayKey.days(from: today, to: entry.date)
                        HStack(spacing: 10) {
                            Image(systemName: i.status == .trial ? "hourglass" : "repeat").foregroundStyle(i.status == .trial ? Brand.warn : Brand.violet).frame(width: 18)
                                .accessibilityLabel(i.status == .trial ? "En prueba" : "Suscripción")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(i.name).fontWeight(.medium)
                                Text(i.status == .trial ? "la prueba acaba; después \(Money.exact(i.amount))" : i.period.label).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.exact(i.amount)).monospacedDigit()
                            Text(DayKey.dmy(entry.date)).monospacedDigit().foregroundStyle(.secondary)
                            Text(relativeDays(n)).foregroundStyle(n <= 2 ? Brand.warn : .secondary).frame(width: 90, alignment: .trailing)
                            if store.isVisible(.gastos), i.status == .active, store.suscripcionLogged(i) {
                                Label("Apuntado este mes", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
                            } else if store.isVisible(.gastos), i.status == .active {
                                Button("Apuntar en Gastos") {
                                    let c = store.logSuscripcionCharge(i)
                                    message = c.map { "Apuntado en \($0)." } ?? "No hay partidas en Gastos."
                                }.controlSize(.small)
                            }
                            Menu {
                                ForEach(["Activa", "Prueba", "Cancelada"], id: \.self) { st in Button(st) { store.setSuscripcionStatus(i, to: st) } }
                            } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Cambiar estado") }
                                .menuStyle(.borderlessButton).fixedSize()
                        }
                    }
                    if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary) }
                }
                Card(title: "Añadir", icon: "plus.circle") {
                    HStack {
                        TextField("Servicio", text: $name)
                        TextField("Importe", text: $amount).frame(width: 90)
                        ChoiceMenu(options: Self.periods, current: every, width: 110) { every = $0 }
                        DatePicker(trial ? "Acaba el" : "Próximo cobro", selection: $date, displayedComponents: .date).fixedSize()
                    }
                    HStack {
                        ChoiceMenu(options: [""] + store.expenseCategories, current: category, width: 200, emptyLabel: "Partida de Gastos") { category = $0 }
                        Toggle("Es una prueba gratuita", isOn: $trial).toggleStyle(.checkbox)
                        Spacer()
                        Button("Guardar") {
                            store.addSuscripcion(name: name.trimmingCharacters(in: .whitespaces), amount: Money.parse(amount), every: every, date: DayKey.calendar().startOfDay(for: date), category: category, trial: trial)
                            name = ""; amount = ""; trial = false
                        }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Money.parse(amount) <= 0)
                    }
                }
                if !cancelled.isEmpty {
                    Card(title: "Canceladas", icon: "xmark.circle") {
                        ForEach(cancelled) { i in
                            HStack {
                                Text(i.name).foregroundStyle(.secondary)
                                Spacer()
                                Text("ahorras \(Money.format(i.yearlyCost)) al año").font(.callout).foregroundStyle(.secondary)
                                Button("Reactivar") { store.setSuscripcionStatus(i, to: "Activa") }.controlSize(.small)
                            }
                        }
                    }
                }
                NoteTables(file: file, icon: "tablecells")
                Button("Abrir la nota") { store.pendingNote = file }.buttonStyle(.accentLink)
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Suscripciones")
    }
}
