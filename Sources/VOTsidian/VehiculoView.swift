import SwiftUI

struct VehiculoView: View {
    @Environment(Store.self) private var store
    private let file = VaultPath.vehiculo
    @State private var kind = 0   // 0 = repostaje, 1 = taller
    @State private var date = Date()
    @State private var km = ""
    @State private var liters = ""
    @State private var amount = ""
    @State private var what = ""
    @State private var shop = ""
    @State private var everyKm = ""
    @State private var everyMonths = ""
    @State private var toGastos = true

    var body: some View {
        let _ = BodyCounter.hit("VehiculoView")
        let v = store.vehiculo
        let today = DayKey.today()
        let year = DayKey.calendar().component(.year, from: today)
        let spent = v.spent(year: year)
        let next = v.nextServices(today: today)
        let tasks = store.tasks(in: file).filter { !$0.done }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MissingNoteBanner(module: .vehiculo)
                HStack(spacing: 12) {
                    Tile(title: "Km", value: v.currentKm.map(Vehiculo.kmText) ?? "–", note: v.plate.isEmpty ? nil : v.plate)
                    Tile(title: "Consumo", value: v.consumption.map { fmt($0) + " L/100" } ?? "–", note: v.consumption == nil ? "con dos repostajes con km y litros" : "de depósito lleno a lleno")
                    Tile(title: "Gastado en \(year)", value: Money.format(spent.service + spent.fuel),
                         note: spent.service + spent.fuel > 0 ? "\(Money.format(spent.fuel)) combustible · \(Money.format(spent.service)) taller" : nil)
                }
                Card(title: "Avisos", icon: "bell",
                     info: "Lo que vence en la tabla Fechas avisa 30 días antes. El mantenimiento con «Cada (km)» o «Cada (meses)» avisa cuando faltan menos de 1.000 km o 30 días.") {
                    let alerts = store.vehiculoAlerts(today: today)
                    AlertList(alerts: alerts, emptyText: "Nada vence pronto.")
                    ForEach(tasks) { TaskRow(task: $0) }
                }
                HStack(alignment: .top, spacing: 16) {
                    Card(title: "Fechas", icon: "calendar") {
                        if v.dues.isEmpty { EmptyNote("Pon la fecha de la ITV, el seguro… en la columna «Vence» de la tabla Fechas.", icon: "calendar") }
                        ForEach(v.dues) { d in
                            let n = DayKey.days(from: today, to: d.date)
                            HStack {
                                Image(systemName: n < 0 ? "xmark.octagon.fill" : n <= 30 ? "exclamationmark.triangle.fill" : "checkmark.circle")
                                    .foregroundStyle(n < 0 ? Brand.bad : n <= 30 ? Brand.warn : Brand.accent)
                                    .accessibilityLabel(n < 0 ? "Vencido" : n <= 30 ? "Vence pronto" : "En vigor")
                                Text(d.name).fontWeight(.medium)
                                Spacer()
                                Text(DayKey.dmy(d.date)).monospacedDigit().foregroundStyle(.secondary)
                                Text(n < 0 ? "venció \(relativeDays(n))" : relativeDays(n)).frame(width: 110, alignment: .trailing)
                            }
                        }
                    }
                    Card(title: "Próximo mantenimiento", icon: "wrench.and.screwdriver") {
                        if next.isEmpty { EmptyNote("Al apuntar una visita al taller, pon cada cuántos km o meses toca.", icon: "wrench.and.screwdriver") }
                        ForEach(next) { s in
                            HStack {
                                Image(systemName: s.isDue ? "exclamationmark.octagon.fill" : s.isSoon ? "exclamationmark.triangle.fill" : "checkmark.circle")
                                    .foregroundStyle(s.isDue ? Brand.bad : s.isSoon ? Brand.warn : Brand.accent)
                                    .accessibilityLabel(s.isDue ? "Toca ya" : s.isSoon ? "Toca pronto" : "Al día")
                                Text(s.what).fontWeight(.medium)
                                Spacer()
                                Text([s.km.map(Vehiculo.kmText), s.date.map(DayKey.dmy)].compactMap { $0 }.joined(separator: " · "))
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Card(title: "Apuntar", icon: "plus.circle") {
                    Picker("", selection: $kind) {
                        Text("Repostaje").tag(0)
                        Text("Taller").tag(1)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 240)
                    HStack {
                        DatePicker("Día", selection: $date, in: ...Date(), displayedComponents: .date).frame(width: 220)
                        TextField("Km", text: $km).frame(width: 110)
                        if kind == 0 {
                            TextField("Litros", text: $liters).frame(width: 90)
                            TextField("Importe", text: $amount).frame(width: 90)
                        } else {
                            TextField("Qué (aceite, ruedas…)", text: $what)
                            TextField("Taller", text: $shop)
                        }
                    }
                    HStack {
                        if kind == 1 {
                            TextField("Coste", text: $amount).frame(width: 90)
                            TextField("Cada (km)", text: $everyKm).frame(width: 100)
                            TextField("Cada (meses)", text: $everyMonths).frame(width: 110)
                        }
                        if store.isVisible(.gastos) { Toggle("Apuntar también en Gastos", isOn: $toGastos).toggleStyle(.checkbox) }
                        Spacer()
                        Button("Guardar", action: save).buttonStyle(.borderedProminent)
                            .disabled(kind == 0 ? liters.isEmpty && amount.isEmpty : what.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Card(title: "Ficha", icon: "car", info: "Pulsa intro para guardar cada campo. Los km se actualizan solos con lo que apuntas.") {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                        ficha("Nombre", "nombre")
                        ficha("Matrícula", "matricula")
                        ficha("Km", "km")
                    }
                }
                NoteTables(file: file, icon: "tablecells")
                Button("Abrir la nota") { store.pendingNote = file }.buttonStyle(.accentLink)
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle(v.name)
    }

    private func save() {
        let day = DayKey.calendar().startOfDay(for: date)
        let cost = Vehiculo.money(amount)
        if kind == 0 {
            store.addRepostaje(date: day, km: Vehiculo.km(km), liters: MD.number(liters), amount: cost, expense: toGastos && store.isVisible(.gastos))
        } else {
            store.addMantenimiento(date: day, km: Vehiculo.km(km), what: what.trimmingCharacters(in: .whitespaces), shop: shop, cost: cost,
                                   everyKm: Vehiculo.km(everyKm), everyMonths: MD.int(MD.number(everyMonths)).flatMap { $0 > 0 ? $0 : nil },
                                   expense: toGastos && store.isVisible(.gastos))
        }
        km = ""; liters = ""; amount = ""; what = ""; shop = ""; everyKm = ""; everyMonths = ""
    }

    private func ficha(_ label: String, _ key: String) -> some View {
        GridRow { Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing); PropertyField(file: file, key: key, width: 320) }
    }
}
